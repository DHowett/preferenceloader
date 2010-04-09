#import <Preferences/PSSpecifier.h>
#import <Preferences/PSListController.h>

extern "C" NSArray* SpecifiersFromPlist(NSDictionary* plist,
					PSSpecifier* prevSpec,
					id target,
					NSString* plistName,
					NSBundle* curBundle,
					NSString** pTitle,
					NSString** pSpecifierID,
					PSListController* callerList,
					NSMutableArray** pBundleControllers);

@interface PLCustomListController: PSListController { }
@end
@implementation PLCustomListController
- (id)bundle {
	return [[self specifier] propertyForKey:@"pl_bundle"];
}
@end

@interface PLLocalizedListController: PLCustomListController { }
@end
@implementation PLLocalizedListController
- (id)title {
	return [[self bundle] localizedStringForKey:[super title] value:[super title] table:nil];
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

%hook PrefsListController
static NSMutableArray *_loadedSpecifiers = [[NSMutableArray alloc] init];

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
				[specifier setProperty:bundlePath forKey:@"lazy-bundle"];
			} else {
				MSHookIvar<Class>(specifier, "detailControllerClass") = isLocalizedBundle ? [PLLocalizedListController class] : [PLCustomListController class];
				[specifier setProperty:prefBundle forKey:@"pl_bundle"];
			}
			[specifier setProperty:[NSNumber numberWithBool:1] forKey:@"useEtched"];
			[_loadedSpecifiers addObject:specifier];
		}
		[self insertSpecifier:[PSSpecifier emptyGroupSpecifier] atEndOfGroup:group];
		[self insertContiguousSpecifiers:_loadedSpecifiers atEndOfGroup:group+1];
	}
	return MSHookIvar<id>(self, "_specifiers");
}
%end

__attribute__((constructor)) static void _plInit() {
	%init;
	if([UIDevice instancesRespondToSelector:@selector(isWildcat)])
		%init(iPad);
}
