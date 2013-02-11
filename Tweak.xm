#import <Preferences/PSSpecifier.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSBundleController.h>
#import <Preferences/PSTableCell.h>
#import <substrate.h>

#if DEBUG
#	define PLLog(...) NSLog(@"PreferenceLoader! %s:%d: %@", __FILE__, __LINE__, [NSString stringWithFormat:__VA_ARGS__])
#else
#	define PLLog(...)
#endif

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


extern NSString *const PSBundlePathKey;
extern NSString *const PSLazilyLoadedBundleKey;
extern NSString *const PSBundleIsControllerKey;
extern NSString *const PSActionKey;
extern NSString *const PSTitleKey;

// Weak (3.2+, dlsym)
static NSString **pPSTableCellUseEtchedAppearanceKey = NULL;
static NSString **pPSFooterTextGroupKey = NULL;
static NSString **pPSStaticTextGroupKey = NULL;
/* }}} */

/* {{{ Prototypes */
static NSArray *generateErrorSpecifiersWithText(NSString *errorText);
static bool checkFilter(NSDictionary *filter);
/* }}} */

/* {{{ UIDevice 3.2 Additions */
@interface UIDevice (iPad)
- (BOOL)isWildcat;
@end
/* }}} */

/* {{{ Constants */
static NSString *const PLBundleKey = @"pl_bundle";
static NSString *const PLFilterKey = @"pl_filter";
static NSString *const PLAlternatePlistNameKey = @"pl_alt_plist_name";
/* }}} */

/* {{{ Locals */
static BOOL _Firmware_lt_60 = NO;
/* }}} */

/* {{{ Preferences Controllers */
@interface PLCustomListController: PSListController { }
@end
@implementation PLCustomListController
- (id)bundle {
	return [[self specifier] propertyForKey:PLBundleKey];
}

- (id)specifiers {
	if(!_specifiers) {
		PLLog(@"loading specifiers for a custom bundle.");
		NSString *alternatePlistName = [[self specifier] propertyForKey:PLAlternatePlistNameKey];
		if(alternatePlistName)
			_specifiers = [[super loadSpecifiersFromPlistName:alternatePlistName target:self] retain];
		else
			_specifiers = [super specifiers];
		if(!_specifiers || [_specifiers count] == 0) {
			[_specifiers release];
			NSString *errorText = @"There appears to be an error with with these preferences!";
			_specifiers = [[NSArray alloc] initWithArray:generateErrorSpecifiersWithText(errorText)];
		} else {
			NSMutableArray *removals = [NSMutableArray array];
			for(PSSpecifier *spec in _specifiers) {
				if(MSHookIvar<int>(spec, "cellType") == PSLinkCell && ![spec propertyForKey:PSBundlePathKey]) {
					MSHookIvar<Class>(spec, "detailControllerClass") = [self class];
					[spec setProperty:[[self specifier] propertyForKey:PLBundleKey] forKey:PLBundleKey];
				}

				if(!checkFilter([spec propertyForKey:PLFilterKey]))
					[removals addObject:spec];

				if(removals.count > 0) {
					NSMutableArray *newSpecifiers = [_specifiers mutableCopy];
					[_specifiers release];
					[newSpecifiers removeObjectsInArray:removals];
					_specifiers = newSpecifiers;
				}
			}
		}
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
		PLLog(@"Localizing specifiers for a localized bundle.");
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
			if(pPSFooterTextGroupKey) {
				NSString *value = [spec propertyForKey:*pPSFooterTextGroupKey];
				if(value)
					[spec setProperty:[[self bundle] localizedStringForKey:value value:value table:nil] forKey:*pPSFooterTextGroupKey];
			}
		}
	}
	return _specifiers;
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
		PLLog(@"Generating error specifiers for a failed bundle :(");
		NSString *const errorText = [NSString stringWithFormat:@"There was an error loading the preference bundle for %@.", [[self specifier] name]];
		_specifiers = [[NSArray alloc] initWithArray:generateErrorSpecifiersWithText(errorText)];
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

static NSArray *generateErrorSpecifiersWithText(NSString *errorText) {
	NSMutableArray *errorSpecifiers = [NSMutableArray array];
	if(pPSFooterTextGroupKey) {
		PSSpecifier *spec = [PSSpecifier emptyGroupSpecifier];
		[spec setProperty:errorText forKey:*pPSFooterTextGroupKey];
		[errorSpecifiers addObject:spec];
	} else {
		if(pPSStaticTextGroupKey) {
			PSSpecifier *spec = [PSSpecifier emptyGroupSpecifier];
			[spec setProperty:[NSNumber numberWithBool:YES] forKey:*pPSStaticTextGroupKey];
			[errorSpecifiers addObject:spec];
			spec = [PSSpecifier preferenceSpecifierNamed:errorText target:nil set:nil get:nil detail:nil cell:[PSTableCell cellTypeFromString:@"PSTitleValueCell"] edit:nil];
			[errorSpecifiers addObject:spec];
		}
	}
	return errorSpecifiers;
}

static bool checkFilter(NSDictionary *filter) {
	if(!filter) return true;
	bool valid = true;

	PLLog(@"Checking filter %@", filter);

	NSArray *coreFoundationVersion = [filter objectForKey:@"CoreFoundationVersion"];
	if(coreFoundationVersion && coreFoundationVersion.count > 0) {
		NSNumber *lowerBound = [coreFoundationVersion objectAtIndex:0];
		NSNumber *upperBound = coreFoundationVersion.count > 1 ? [coreFoundationVersion objectAtIndex:1] : nil;
		PLLog(@"%@ <= CF Version (%f) < %@", lowerBound, kCFCoreFoundationVersionNumber, upperBound);
		valid = valid && (kCFCoreFoundationVersionNumber >= lowerBound.floatValue) && (upperBound ? (kCFCoreFoundationVersionNumber < upperBound.floatValue) : true);
	}
	PLLog(valid ? @"Filter matched" : @"Filter did not match");
	return valid;
}
/* }}} */

/* {{{ Hooks */
static void pl_loadFailedBundle(NSString *bundlePath, PSSpecifier *specifier) {
	PLLog(@"lazyLoadBundle:%@ (bundle path %@) failed.", specifier, bundlePath);
	NSLog(@"Failed to load PreferenceBundle at %@.", bundlePath);
	MSHookIvar<Class>(specifier, "detailControllerClass") = [PLFailedBundleListController class];
	[specifier removePropertyForKey:PSBundleIsControllerKey];
	[specifier removePropertyForKey:PSActionKey];
	[specifier removePropertyForKey:PSBundlePathKey];
	[specifier removePropertyForKey:PSLazilyLoadedBundleKey];
}

%group Firmware_lt_60
%hook PrefsRootController
- (void)lazyLoadBundle:(PSSpecifier *)specifier {
	NSString *bundlePath = [[specifier propertyForKey:PSLazilyLoadedBundleKey] retain];
	%orig; // NB: This removes the PSLazilyLoadedBundleKey property.
	if(![[NSBundle bundleWithPath:bundlePath] isLoaded]) {
		pl_loadFailedBundle(bundlePath, specifier);
	}
	[bundlePath release];
}
%end
%end

%group Firmware_ge_60
%hook PrefsListController
- (void)lazyLoadBundle:(PSSpecifier *)specifier {
	NSString *bundlePath = [[specifier propertyForKey:PSLazilyLoadedBundleKey] retain];
	%orig; // NB: This removes the PSLazilyLoadedBundleKey property.
	if(![[NSBundle bundleWithPath:bundlePath] isLoaded]) {
		pl_loadFailedBundle(bundlePath, specifier);
	}
	[bundlePath release];
}
%end
%end

%hook PrefsListController
static NSMutableArray *_loadedSpecifiers = nil;
static int _extraPrefsGroupSectionID = 0;

/* {{{ iPad Hooks */
%group iPad
- (NSString *)tableView:(id)view titleForHeaderInSection:(int)section {
	if([_loadedSpecifiers count] == 0) return %orig;
	if(section == _extraPrefsGroupSectionID) return _Firmware_lt_60 ? @"Extensions" : NULL;
	return %orig;
}

- (float)tableView:(id)view heightForHeaderInSection:(int)section {
	if([_loadedSpecifiers count] == 0) return %orig;
	if(section == _extraPrefsGroupSectionID) return _Firmware_lt_60 ? 22.0f : 10.f;
	return %orig;
}
%end
/* }}} */

- (id)specifiers {
	bool first = (MSHookIvar<id>(self, "_specifiers") == nil);
	if(first) {
		PLLog(@"initial invocation for -specifiers");
		%orig;
		[_loadedSpecifiers release];
		_loadedSpecifiers = [[NSMutableArray alloc] init];
		NSArray *subpaths = [[NSFileManager defaultManager] subpathsOfDirectoryAtPath:@"/Library/PreferenceLoader/Preferences" error:NULL];
		for(NSString *item in subpaths) {
			if(![[item pathExtension] isEqualToString:@"plist"]) continue;
			PLLog(@"processing %@", item);
			NSString *fullPath = [NSString stringWithFormat:@"/Library/PreferenceLoader/Preferences/%@", item];
			NSDictionary *plPlist = [NSDictionary dictionaryWithContentsOfFile:fullPath];
			if(!checkFilter([plPlist objectForKey:@"filter"] ?: [plPlist objectForKey:PLFilterKey])) continue;

			NSDictionary *entry = [plPlist objectForKey:@"entry"];
			if(!entry) continue;
			PLLog(@"found an entry key for %@!", item);

			if(!checkFilter([entry objectForKey:PLFilterKey])) continue;

			NSDictionary *specifierPlist = [NSDictionary dictionaryWithObjectsAndKeys:[NSArray arrayWithObjects:entry, nil], @"items", nil];

			BOOL isBundle = [entry objectForKey:@"bundle"] != nil;
			BOOL isLocalizedBundle = ![[[fullPath stringByDeletingLastPathComponent] lastPathComponent] isEqualToString:@"Preferences"];

			NSBundle *prefBundle;
			NSString *bundleName = [entry objectForKey:@"bundle"];
			NSString *bundlePath = [entry objectForKey:@"bundlePath"];
			NSArray *bundleControllers = [[NSArray alloc] init];

			if(isBundle) {
				// Second Try (bundlePath key failed)
				if(![[NSFileManager defaultManager] fileExistsAtPath:bundlePath])
					bundlePath = [NSString stringWithFormat:@"/Library/PreferenceBundles/%@.bundle", bundleName];

				// Third Try (/Library failed)
				if(![[NSFileManager defaultManager] fileExistsAtPath:bundlePath])
					bundlePath = [NSString stringWithFormat:@"/System/Library/PreferenceBundles/%@.bundle", bundleName];

				// Really? (/System/Library failed...)
				if(![[NSFileManager defaultManager] fileExistsAtPath:bundlePath]) {
					NSLog(@"Discarding specifier for missing isBundle bundle %@.", bundleName);
					continue;
				}
				prefBundle = [NSBundle bundleWithPath:bundlePath];
				PLLog(@"is a bundle: %@!", prefBundle);
			} else {
				prefBundle = [NSBundle bundleWithPath:[fullPath stringByDeletingLastPathComponent]];
				PLLog(@"is NOT a bundle, so we're giving it %@!", prefBundle);
			}

			PLLog(@"loading specifiers!");
			NSArray *specs = SpecifiersFromPlist(specifierPlist, nil, _Firmware_lt_60 ? [self rootController] : self, item, prefBundle, NULL, NULL, (PSListController*)self, &bundleControllers);
			PLLog(@"loaded specifiers!");

			// If there are any PSBundleControllers, add them to our list.
			if(bundleControllers) {
				[MSHookIvar<NSMutableArray *>(self, "_bundleControllers") addObjectsFromArray:bundleControllers];
				[bundleControllers release];
			}

			if([specs count] == 0) continue;
			PLLog(@"It's confirmed! There are Specifiers here, Captain!");

			if(isBundle) {
				 // Only set lazy-bundle for isController specifiers.
				if([[entry objectForKey:@"isController"] boolValue]) {
					for(PSSpecifier *specifier in specs) {
						[specifier setProperty:bundlePath forKey:PSLazilyLoadedBundleKey];
					}
				}
			} else {
				// There really should only be one specifier.
				PSSpecifier *specifier = [specs objectAtIndex:0];
				MSHookIvar<Class>(specifier, "detailControllerClass") = isLocalizedBundle ? [PLLocalizedListController class] : [PLCustomListController class];
				[specifier setProperty:prefBundle forKey:PLBundleKey];

				NSString *plistName = [[fullPath stringByDeletingPathExtension] lastPathComponent];
				if(![[specifier propertyForKey:PSTitleKey] isEqualToString:plistName]) {
					[specifier setProperty:plistName forKey:PLAlternatePlistNameKey];
				}
			}

			// But it's possible for there to be more than one with an isController == 0 (PSBundleController) bundle.
			// so, set all the specifiers to etched mode (if necessary).
			if(pPSTableCellUseEtchedAppearanceKey && [UIDevice instancesRespondToSelector:@selector(isWildcat)] && [[UIDevice currentDevice] isWildcat])
				for(PSSpecifier *specifier in specs) {
					[specifier setProperty:[NSNumber numberWithBool:1] forKey:*pPSTableCellUseEtchedAppearanceKey];
				}

			PLLog(@"appending to the array!");
			[_loadedSpecifiers addObjectsFromArray:specs];
		}

		[_loadedSpecifiers sortUsingFunction:&PSSpecifierSort context:NULL];

		if([_loadedSpecifiers count] > 0) {
			PLLog(@"so we gots us some specifiers! that's awesome! let's add them to the list...");
			PSSpecifier *groupSpecifier = [PSSpecifier groupSpecifierWithName:_Firmware_lt_60 ? @"Extensions" : nil];
			[_loadedSpecifiers insertObject:groupSpecifier atIndex:0];
			NSMutableArray *_specifiers = MSHookIvar<NSMutableArray *>(self, "_specifiers");
			int group, row;
			int firstindex;
			if ([self getGroup:&group row:&row ofSpecifierID:_Firmware_lt_60 ? @"General" : @"TWITTER"]) {
				firstindex = [self indexOfGroup:group] + [[self specifiersInGroup:group] count];
				PLLog(@"Adding to the end of group %d at index %d", group, firstindex);
			} else {
				firstindex = [_specifiers count];
				PLLog(@"Adding to the end of entire list");
			}
			NSIndexSet *indices = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(firstindex, [_loadedSpecifiers count])];
			[_specifiers insertObjects:_loadedSpecifiers atIndexes:indices];
			PLLog(@"getting group index");
			NSUInteger groupIndex = 0;
			for(PSSpecifier *spec in _specifiers) {
				if(MSHookIvar<int>(spec, "cellType") != PSGroupCell) continue;
				if(spec == groupSpecifier) break;
				++groupIndex;
			}
			_extraPrefsGroupSectionID = groupIndex;
			PLLog(@"group index is %d", _extraPrefsGroupSectionID);
		}
	}
	return MSHookIvar<id>(self, "_specifiers");
}
%end

%hook NSBundle
+ (NSBundle *)bundleWithPath:(NSString *)path {
	NSString *newPath = nil;
	NSRange sysRange = [path rangeOfString:@"/System/Library/PreferenceBundles" options:0];
	if(sysRange.location != NSNotFound) {
		newPath = [path stringByReplacingCharactersInRange:sysRange withString:@"/Library/PreferenceBundles"];
	}
	if(newPath && [[NSFileManager defaultManager] fileExistsAtPath:newPath]) {
		// /Library/PreferenceBundles will override /System/Library/PreferenceBundles.
		path = newPath;
	}
	return %orig;
}
%end
/* }}} */

%ctor {
	%init;
	if([UIDevice instancesRespondToSelector:@selector(isWildcat)] && [[UIDevice currentDevice] isWildcat])
		%init(iPad);

	if([%c(PrefsRootController) respondsToSelector:@selector(lazyLoadBundle:)]) {
		_Firmware_lt_60 = YES;
		%init(Firmware_lt_60);
	} else {
		_Firmware_lt_60 = NO;
		%init(Firmware_ge_60);
	}

	void *preferencesHandle = dlopen("/System/Library/PrivateFrameworks/Preferences.framework/Preferences", RTLD_LAZY | RTLD_NOLOAD);
	if(preferencesHandle) {
		pPSTableCellUseEtchedAppearanceKey = (NSString **)dlsym(preferencesHandle, "PSTableCellUseEtchedAppearanceKey");
		pPSFooterTextGroupKey = (NSString **)dlsym(preferencesHandle, "PSFooterTextGroupKey");
		pPSStaticTextGroupKey = (NSString **)dlsym(preferencesHandle, "PSStaticTextGroupKey");
		dlclose(preferencesHandle);
	}
}
