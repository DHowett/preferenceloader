#import <Preferences/Preferences.h>

@interface PSListController (libprefs)
- (NSArray *)specifiersFromEntry:(NSDictionary *)entry sourcePreferenceLoaderBundlePath:(NSString *)sourceBundlePath title:(NSString *)title;
@end

extern NSString *const PLFilterKey;

@interface PSSpecifier (libprefs)
+ (BOOL)environmentPassesPreferenceLoaderFilter:(NSDictionary *)filter;
@end

@interface PLCustomListController: PSListController { }
@end

@interface PLLocalizedListController: PLCustomListController { }
@end
