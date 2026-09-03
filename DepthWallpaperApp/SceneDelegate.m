#import "SceneDelegate.h"
#import "ViewController.h"

@implementation SceneDelegate

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
    if (![scene isKindOfClass:[UIWindowScene class]]) {
        return;
    }

    UIWindowScene *windowScene = (UIWindowScene *)scene;
    self.window = [[UIWindow alloc] initWithWindowScene:windowScene];
    self.window.backgroundColor = UIColor.systemBackgroundColor;
    UIViewController *root = [[ViewController alloc] init];
    self.window.rootViewController = root;
    [self.window makeKeyAndVisible];
}

- (void)sceneDidBecomeActive:(UIScene *)scene {
    [self.window.rootViewController.view setNeedsLayout];
}

@end
