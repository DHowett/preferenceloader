#import <Preferences/PSSpecifier.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSTableCell.h>
#import "PSKeys.h"

/* {{{ Imports (Preferences.framework) */
extern "C" NSArray* SpecifiersFromPlist(NSDictionary* plist,
					PSSpecifier* prevSpec,
					id target,
					NSString* plistName,
					NSBundle* curBundle,
					NSString** pTitle,
					NSString** pSpecifierID,
					PSListController* callerList,
					NSMutableArray** pBundleControllers);

// Weak (3.2+, dlsym)
static NSString **pPSTableCellUseEtchedAppearanceKey = NULL;
static NSString **pPSFooterTextGroupKey = NULL;
/* }}} */

/* {{{ UIDevice 3.2 Additions */
@interface UIDevice (iPad)
- (BOOL)isWildcat;
@end
/* }}} */

/* {{{ Preferences Controllers */
@interface PLCustomListController: PSListController { }
@end
@implementation PLCustomListController
- (id)bundle {
	return [[self specifier] propertyForKey:@"pl_bundle"];
}
@end

@interface PLFailedBundleListController: PSListController { }
@end
@implementation PLFailedBundleListController
- (id)navigationTitle {
	return @"Error";
}

- (id)specifiers {
	if(!_specifiers) {
		NSString *const errorText = [NSString stringWithFormat:@"There was an error loading the preference bundle for %@.", [[self specifier] name]];
		NSMutableArray *newSpecifiers = [[NSMutableArray alloc] init];
		if(pPSFooterTextGroupKey) {
			PSSpecifier *spec = [PSSpecifier emptyGroupSpecifier];
			[spec setProperty:errorText forKey:*pPSFooterTextGroupKey];
			[newSpecifiers addObject:spec];
		} else {
			PSSpecifier *spec = [PSSpecifier emptyGroupSpecifier];
			[spec setProperty:[NSNumber numberWithBool:YES] forKey:PSStaticTextGroupKey];
			[newSpecifiers addObject:spec];
			spec = [PSSpecifier preferenceSpecifierNamed:errorText target:nil set:nil get:nil detail:nil cell:[PSTableCell cellTypeFromString:@"PSTitleValueCell"] edit:nil];
			[newSpecifiers addObject:spec];
		}
		_specifiers = newSpecifiers;
	}
	return _specifiers;
}
@end

@interface PLLocalizedListController: PLCustomListController { }
@end
@implementation PLLocalizedListController
- (id)navigationTitle {
	return [[self bundle] localizedStringForKey:[super navigationTitle] value:[super navigationTitle] table:nil];
}

- (id)specifiers {
	if(!_specifiers) {
		_specifiers = [super specifiers];
		for(PSSpecifier *spec in _specifiers) {
			if([spec name]) [spec setName:[[self bundle] localizedStringForKey:[spec name] value:[spec name] table:nil]];
			if([spec titleDictionary]) {
				NSMutableDictionary *newTitles = [NSMutableDictionary dictionary];
				for(NSString *key in [spec titleDictionary]) {
					NSString *value = [[spec titleDictionary] objectForKey:key];
					[newTitles setObject:[[self bundle] localizedStringForKey:value value:value table:nil] forKey:key];
				}
				[spec setTitleDictionary:newTitles];
			}
		}
	}
	return _specifiers;
}
@end
/* }}} */

/* {{{ Helper Functions */
static NSInteger PSSpecifierSort(PSSpecifier *a1, PSSpecifier *a2, void *context) {
	NSString *string1 = [a1 name];
	NSString *string2 = [a2 name];
	return [string1 localizedCaseInsensitiveCompare:string2];
}
/* }}} */

/* {{{ Hooks */
%hook PrefsRootController
- (void)lazyLoadBundle:(PSSpecifier *)specifier {
	NSString *bundlePath = [[specifier propertyForKey:PSLazilyLoadedBundleKey] retain];
	%orig; // NB: This removes the PSLazilyLoadedBundleKey property.
	if(![[NSBundle bundleWithPath:bundlePath] isLoaded]) {
		NSLog(@"Failed to load PreferenceBundle at %@.", bundlePath);
		MSHookIvar<Class>(specifier, "detailControllerClass") = [PLFailedBundleListController class];
		[specifier removePropertyForKey:PSBundleIsControllerKey];
		[specifier removePropertyForKey:PSActionKey];
		[specifier removePropertyForKey:PSBundlePathKey];
		[specifier removePropertyForKey:PSLazilyLoadedBundleKey];
	}
	[bundlePath release];
}
%end

%hook PrefsListController
static NSMutableArray *_loadedSpecifiers = [[NSMutableArray alloc] init];

/* {{{ iPad Hooks */
%group iPad
- (NSString *)tableView:(id)view titleForHeaderInSection:(int)section {
	if([_loadedSpecifiers count] == 0) return %orig;
	int groupCount = [MSHookIvar<NSMutableArray *>(self, "_groups") count];
	if(section == groupCount - 2) return @"Extensions";
	return %orig;
}

- (float)tableView:(id)view heightForHeaderInSection:(int)section {
	if([_loadedSpecifiers count] == 0) return %orig;
	int groupCount = [MSHookIvar<NSMutableArray *>(self, "_groups") count];
	if(section == groupCount - 2) return 22.0f;
	return %orig;
}
%end
/* }}} */

- (id)specifiers {
	bool first = (MSHookIvar<id>(self, "_specifiers") == nil);
	if(first) {
		%orig;
		int group, row;
		[self getGroup:&group row:&row ofSpecifier:[self specifierForID:@"General"]];

		NSArray *subpaths = [[NSFileManager defaultManager] subpathsOfDirectoryAtPath:@"/Library/PreferenceLoader/Preferences" error:NULL];
		for(NSString *item in subpaths) {
			if(![[item pathExtension] isEqualToString:@"plist"]) continue;
			NSString *fullPath = [NSString stringWithFormat:@"/Library/PreferenceLoader/Preferences/%@", item];
			NSDictionary *plPlist = [NSDictionary dictionaryWithContentsOfFile:fullPath];
			NSDictionary *entry = [plPlist objectForKey:@"entry"];
			NSDictionary *specifierPlist = [NSDictionary dictionaryWithObjectsAndKeys:[NSArray arrayWithObjects:entry, nil], @"items", nil];

			BOOL isController = [[entry objectForKey:@"isController"] boolValue];
			BOOL isLocalizedBundle = ![[[fullPath stringByDeletingLastPathComponent] lastPathComponent] isEqualToString:@"Preferences"];

			NSBundle *prefBundle;
			NSString *bundleName = [entry objectForKey:@"bundle"];
			NSString *bundlePath = [entry objectForKey:@"bundlePath"];
			if(isController) {
				// Second Try (bundlePath key failed)
				if(![[NSFileManager defaultManager] fileExistsAtPath:bundlePath])
					bundlePath = [NSString stringWithFormat:@"/Library/PreferenceBundles/%@.bundle", bundleName];

				// Third Try (/Library failed)
				if(![[NSFileManager defaultManager] fileExistsAtPath:bundlePath])
					bundlePath = [NSString stringWithFormat:@"/System/Library/PreferenceBundles/%@.bundle", bundleName];

				// Really? (/System/Library failed...)
				if(![[NSFileManager defaultManager] fileExistsAtPath:bundlePath]) {
					NSLog(@"Discarding specifier for missing isController bundle %@.", bundleName);
					continue;
				}

				prefBundle = [NSBundle bundleWithPath:bundlePath];
			} else {
				prefBundle = [NSBundle bundleWithPath:[fullPath stringByDeletingLastPathComponent]];
			}
			NSArray *specs = SpecifiersFromPlist(specifierPlist, nil, [self rootController], item, prefBundle, NULL, NULL, (PSListController*)self, NULL);
			PSSpecifier *specifier = [specs objectAtIndex:0];
			if(isController) {
				[specifier setProperty:bundlePath forKey:PSLazilyLoadedBundleKey];
			} else {
				MSHookIvar<Class>(specifier, "detailControllerClass") = isLocalizedBundle ? [PLLocalizedListController class] : [PLCustomListController class];
				[specifier setProperty:prefBundle forKey:@"pl_bundle"];
			}
			if(pPSTableCellUseEtchedAppearanceKey && [UIDevice instancesRespondToSelector:@selector(isWildcat)] && [[UIDevice currentDevice] isWildcat])
				[specifier setProperty:[NSNumber numberWithBool:1] forKey:*pPSTableCellUseEtchedAppearanceKey];
			[_loadedSpecifiers addObject:specifier];
		}

		[_loadedSpecifiers sortUsingFunction:&PSSpecifierSort context:NULL];

		if([_loadedSpecifiers count] > 0) {
			[self insertSpecifier:[PSSpecifier emptyGroupSpecifier] atEndOfGroup:group];
			[self insertContiguousSpecifiers:_loadedSpecifiers atEndOfGroup:group+1];
		}
	}
	return MSHookIvar<id>(self, "_specifiers");
}
%end
/* }}} */

__attribute__((constructor)) static void _plInit() {
	%init;
	if([UIDevice instancesRespondToSelector:@selector(isWildcat)])
		%init(iPad);

	void *preferencesHandle = dlopen("/System/Library/PrivateFrameworks/Preferences.framework/Preferences", RTLD_LAZY | RTLD_NOLOAD);
	if(preferencesHandle) {
		pPSTableCellUseEtchedAppearanceKey = (NSString **)dlsym(preferencesHandle, "PSTableCellUseEtchedAppearanceKey");
		pPSFooterTextGroupKey = (NSString **)dlsym(preferencesHandle, "PSFooterTextGroupKey");
		dlclose(preferencesHandle);
	}
}
