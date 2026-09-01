#import "AppDelegate.h"
#import "ViewController.h"
#import "SceneDelegate.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // iOS 13+ uses SceneDelegate. Keep a legacy fallback for configurations
    // where scenes are not enabled so the app still launches normally.
    if (@available(iOS 13.0, *)) {
        return YES;
    }

    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.backgroundColor = UIColor.whiteColor;
    self.window.rootViewController = [[ViewController alloc] init];
    [self.window makeKeyAndVisible];
    return YES;
}

- (UISceneConfiguration *)application:(UIApplication *)application
    configurationForConnectingSceneSession:(UISceneSession *)connectingSceneSession
    options:(UISceneConnectionOptions *)options API_AVAILABLE(ios(13.0)) {
    UISceneConfiguration *configuration = [[UISceneConfiguration alloc]
        initWithName:@"Default Configuration"
        sessionRole:connectingSceneSession.role];
    configuration.delegateClass = NSClassFromString(@"SceneDelegate");
    return configuration;
}

@end
