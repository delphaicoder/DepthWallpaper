#import "ViewController.h"
#import <PhotosUI/PhotosUI.h>
#import "../DWShared.h"

@interface ViewController () <PHPickerViewControllerDelegate, UIGestureRecognizerDelegate>
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) UIImageView *previewBackgroundView;
@property (nonatomic, strong) UIImageView *previewCutoutView;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIButton *wallpaperButton;
@property (nonatomic, strong) UIButton *cutoutButton;
@property (nonatomic, strong) UIButton *exportLogButton;
@property (nonatomic, strong) UISwitch *enabledSwitch;
@property (nonatomic, strong) UILabel *wallpaperInfoLabel;
@property (nonatomic, strong) UILabel *cutoutInfoLabel;
@property (nonatomic, strong) UIButton *resetCutoutButton;
@property (nonatomic, strong) UIPanGestureRecognizer *cutoutPanGesture;
@property (nonatomic, strong) UIPinchGestureRecognizer *cutoutPinchGesture;
@property (nonatomic) CGPoint cutoutNormalizedCenter;
@property (nonatomic) CGFloat cutoutScale;
@property (nonatomic, copy) NSString *pickerMode;
@property (nonatomic, strong) UIImage *wallpaperPreview;
@property (nonatomic, strong) UIImage *cutoutPreview;
@property (nonatomic) CGSize wallpaperPixelSize;
@property (nonatomic) CGSize cutoutPixelSize;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Depth Wallpaper";
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    [self setupUI];
    [self resetDiagnosticLog];
    [self logLine:@"App launched."];
    self.cutoutNormalizedCenter = CGPointMake(0.5, 0.5);
    self.cutoutScale = 1.0;
    [self loadExistingState];
}

#pragma mark - UI

- (void)setupUI {
    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.alwaysBounceVertical = YES;
    [self.view addSubview:self.scrollView];

    self.contentView = [[UIView alloc] init];
    self.contentView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scrollView addSubview:self.contentView];

    // Preview giữ đúng tỉ lệ ảnh đã chọn; hai ảnh được chồng 1:1, không AI,
    // không resize/crop chủ thể. Khi cả hai đã chọn thì cutout nằm trên nền.
    self.previewBackgroundView = [[UIImageView alloc] init];
    self.previewBackgroundView.translatesAutoresizingMaskIntoConstraints = NO;
    self.previewBackgroundView.backgroundColor = UIColor.secondarySystemBackgroundColor;
    self.previewBackgroundView.contentMode = UIViewContentModeScaleAspectFit;
    self.previewBackgroundView.clipsToBounds = YES;
    self.previewBackgroundView.layer.cornerRadius = 16.0;
    [self.contentView addSubview:self.previewBackgroundView];

    self.previewCutoutView = [[UIImageView alloc] init];
    self.previewCutoutView.translatesAutoresizingMaskIntoConstraints = NO;
    self.previewCutoutView.contentMode = UIViewContentModeScaleAspectFit;
    self.previewCutoutView.clipsToBounds = YES;
    [self.contentView addSubview:self.previewCutoutView];

    self.previewCutoutView.userInteractionEnabled = YES;
    self.cutoutPanGesture.delegate = self;
    self.cutoutPinchGesture.delegate = self;
    self.cutoutPanGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleCutoutPan:)];
    [self.previewCutoutView addGestureRecognizer:self.cutoutPanGesture];
    self.cutoutPinchGesture = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(handleCutoutPinch:)];
    [self.previewCutoutView addGestureRecognizer:self.cutoutPinchGesture];

    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.font = [UIFont systemFontOfSize:14.0];
    self.statusLabel.textColor = UIColor.secondaryLabelColor;
    self.statusLabel.text = @"Chọn hình nền + PNG đã tách nền. Kích thước không cần giống nhau. Sau đó kéo 1 ngón để di chuyển, chụm 2 ngón để phóng to/thu nhỏ.";
    [self.contentView addSubview:self.statusLabel];

    self.wallpaperButton = [self makeButtonWithTitle:@"1. Chọn hình nền gốc" action:@selector(selectWallpaper)];
    [self.contentView addSubview:self.wallpaperButton];

    self.wallpaperInfoLabel = [self makeInfoLabel];
    self.wallpaperInfoLabel.text = @"Chưa chọn hình nền";
    [self.contentView addSubview:self.wallpaperInfoLabel];

    self.cutoutButton = [self makeButtonWithTitle:@"2. Chọn PNG đã tách nền" action:@selector(selectCutout)];
    [self.contentView addSubview:self.cutoutButton];

    self.cutoutInfoLabel = [self makeInfoLabel];
    self.cutoutInfoLabel.text = @"Chưa chọn ảnh chủ thể";
    [self.contentView addSubview:self.cutoutInfoLabel];

    self.resetCutoutButton = [self makeButtonWithTitle:@"↺ Đặt lại vị trí / kích thước" action:@selector(resetCutoutTransform)];
    self.resetCutoutButton.backgroundColor = UIColor.tertiarySystemBackgroundColor;
    [self.resetCutoutButton setTitleColor:UIColor.labelColor forState:UIControlStateNormal];
    self.resetCutoutButton.titleLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];
    [self.contentView addSubview:self.resetCutoutButton];

    self.exportLogButton = [self makeButtonWithTitle:@"Xuất log (.txt)" action:@selector(exportLog)];
    self.exportLogButton.backgroundColor = UIColor.secondarySystemBackgroundColor;
    [self.exportLogButton setTitleColor:UIColor.labelColor forState:UIControlStateNormal];
    self.exportLogButton.titleLabel.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightSemibold];
    [self.contentView addSubview:self.exportLogButton];

    UILabel *enabledLabel = [self makeInfoLabel];
    enabledLabel.text = @"Bật hiệu ứng chiều sâu";
    [self.contentView addSubview:enabledLabel];

    self.enabledSwitch = [[UISwitch alloc] init];
    self.enabledSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    self.enabledSwitch.on = YES;
    [self.enabledSwitch addTarget:self action:@selector(enabledChanged) forControlEvents:UIControlEventValueChanged];
    [self.contentView addSubview:self.enabledSwitch];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor],

        [self.contentView.leadingAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.leadingAnchor],
        [self.contentView.trailingAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.trailingAnchor],
        [self.contentView.topAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.topAnchor],
        [self.contentView.bottomAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.bottomAnchor],
        [self.contentView.widthAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.widthAnchor],

        [self.previewBackgroundView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:16],
        [self.previewBackgroundView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:20],
        [self.previewBackgroundView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-20],
        [self.previewBackgroundView.heightAnchor constraintEqualToAnchor:self.previewBackgroundView.widthAnchor multiplier:0.5625],
        [self.previewBackgroundView.heightAnchor constraintLessThanOrEqualToConstant:320],

        [self.previewCutoutView.leadingAnchor constraintEqualToAnchor:self.previewBackgroundView.leadingAnchor],
        [self.previewCutoutView.trailingAnchor constraintEqualToAnchor:self.previewBackgroundView.trailingAnchor],
        [self.previewCutoutView.topAnchor constraintEqualToAnchor:self.previewBackgroundView.topAnchor],
        [self.previewCutoutView.bottomAnchor constraintEqualToAnchor:self.previewBackgroundView.bottomAnchor],

        [self.statusLabel.topAnchor constraintEqualToAnchor:self.previewBackgroundView.bottomAnchor constant:12],
        [self.statusLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:24],
        [self.statusLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-24],

        [self.wallpaperButton.topAnchor constraintEqualToAnchor:self.statusLabel.bottomAnchor constant:16],
        [self.wallpaperButton.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:24],
        [self.wallpaperButton.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-24],
        [self.wallpaperButton.heightAnchor constraintGreaterThanOrEqualToConstant:50],

        [self.wallpaperInfoLabel.topAnchor constraintEqualToAnchor:self.wallpaperButton.bottomAnchor constant:5],
        [self.wallpaperInfoLabel.leadingAnchor constraintEqualToAnchor:self.wallpaperButton.leadingAnchor],
        [self.wallpaperInfoLabel.trailingAnchor constraintEqualToAnchor:self.wallpaperButton.trailingAnchor],

        [self.cutoutButton.topAnchor constraintEqualToAnchor:self.wallpaperInfoLabel.bottomAnchor constant:16],
        [self.cutoutButton.leadingAnchor constraintEqualToAnchor:self.wallpaperButton.leadingAnchor],
        [self.cutoutButton.trailingAnchor constraintEqualToAnchor:self.wallpaperButton.trailingAnchor],
        [self.cutoutButton.heightAnchor constraintGreaterThanOrEqualToConstant:50],

        [self.cutoutInfoLabel.topAnchor constraintEqualToAnchor:self.cutoutButton.bottomAnchor constant:5],
        [self.cutoutInfoLabel.leadingAnchor constraintEqualToAnchor:self.cutoutButton.leadingAnchor],
        [self.cutoutInfoLabel.trailingAnchor constraintEqualToAnchor:self.cutoutButton.trailingAnchor],

        [self.resetCutoutButton.topAnchor constraintEqualToAnchor:self.cutoutInfoLabel.bottomAnchor constant:10],
        [self.resetCutoutButton.leadingAnchor constraintEqualToAnchor:self.cutoutButton.leadingAnchor],
        [self.resetCutoutButton.trailingAnchor constraintEqualToAnchor:self.cutoutButton.trailingAnchor],
        [self.resetCutoutButton.heightAnchor constraintGreaterThanOrEqualToConstant:44],

        [self.exportLogButton.topAnchor constraintEqualToAnchor:self.resetCutoutButton.bottomAnchor constant:12],
        [self.exportLogButton.leadingAnchor constraintEqualToAnchor:self.cutoutButton.leadingAnchor],
        [self.exportLogButton.trailingAnchor constraintEqualToAnchor:self.cutoutButton.trailingAnchor],
        [self.exportLogButton.heightAnchor constraintGreaterThanOrEqualToConstant:46],

        [enabledLabel.topAnchor constraintEqualToAnchor:self.exportLogButton.bottomAnchor constant:18],
        [enabledLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:24],
        [self.enabledSwitch.centerYAnchor constraintEqualToAnchor:enabledLabel.centerYAnchor],
        [self.enabledSwitch.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-24],
        [self.contentView.bottomAnchor constraintGreaterThanOrEqualToAnchor:enabledLabel.bottomAnchor constant:28]
    ]];
}

- (UIButton *)makeButtonWithTitle:(NSString *)title action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button setTitle:title forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont boldSystemFontOfSize:17.0];
    button.backgroundColor = UIColor.systemBlueColor;
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    button.layer.cornerRadius = 12.0;
    button.contentEdgeInsets = UIEdgeInsetsMake(12, 18, 12, 18);
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (UILabel *)makeInfoLabel {
    UILabel *label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.font = [UIFont systemFontOfSize:13.0];
    label.textColor = UIColor.secondaryLabelColor;
    label.numberOfLines = 0;
    return label;
}

- (BOOL)shouldAutorotate { return YES; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskAll; }
- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation { return UIInterfaceOrientationLandscapeLeft; }


#pragma mark - Diagnostics

- (NSString *)diagnosticLogPath {
    NSArray<NSURL *> *urls = [[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask];
    NSURL *documentsURL = urls.firstObject;
    if (!documentsURL) return nil;
    return [[documentsURL URLByAppendingPathComponent:@"DepthWallpaperPicker.log.txt"] path];
}

- (void)logLine:(NSString *)line {
    NSString *path = [self diagnosticLogPath];
    if (!path || line.length == 0) return;

    NSString *entry = [NSString stringWithFormat:@"%@ | %@\n", [[NSDate date] descriptionWithLocale:nil], line];
    NSData *data = [entry dataUsingEncoding:NSUTF8StringEncoding];
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!handle) {
        [data writeToFile:path atomically:YES];
        return;
    }
    @try {
        [handle seekToEndOfFile];
        [handle writeData:data];
        [handle closeFile];
    } @catch (__unused NSException *exception) {
        [handle closeFile];
    }
}

- (void)resetDiagnosticLog {
    NSString *path = [self diagnosticLogPath];
    if (!path) return;
    NSString *header = [NSString stringWithFormat:@"DepthWallpaper diagnostic log\nApp version: %@\niOS: %@\nDevice: %@\n\n", [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"unknown", UIDevice.currentDevice.systemVersion ?: @"unknown", UIDevice.currentDevice.model ?: @"unknown"];
    [header writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

- (void)exportLog {
    NSString *path = [self diagnosticLogPath];
    if (!path) return;
    [self logLine:@"User requested diagnostic log export."];

    UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[[NSURL fileURLWithPath:path]] applicationActivities:nil];
    share.popoverPresentationController.sourceView = self.exportLogButton;
    share.popoverPresentationController.sourceRect = self.exportLogButton.bounds;
    [self presentViewController:share animated:YES completion:nil];
}

#pragma mark - Picker

- (void)selectWallpaper {
    self.pickerMode = @"wallpaper";
    [self presentPicker];
}

- (void)selectCutout {
    self.pickerMode = @"cutout";
    [self presentPicker];
}

- (void)presentPicker {
    PHPickerConfiguration *configuration = [[PHPickerConfiguration alloc] initWithPhotoLibrary:PHPhotoLibrary.sharedPhotoLibrary];
    configuration.filter = [PHPickerFilter imagesFilter];
    configuration.selectionLimit = 1;
    if (@available(iOS 14.0, *)) {
        configuration.preferredAssetRepresentationMode = PHPickerConfigurationAssetRepresentationModeCurrent;
    }
    [self logLine:[NSString stringWithFormat:@"Presenting PHPicker. authorization=%ld", (long)[PHPhotoLibrary authorizationStatusForAccessLevel:PHAccessLevelReadWrite]]];
    PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:configuration];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    [picker dismissViewControllerAnimated:YES completion:nil];

    PHPickerResult *result = results.firstObject;
    NSString *mode = [self.pickerMode copy];
    [self logLine:[NSString stringWithFormat:@"Picker finished: mode=%@ resultCount=%lu", mode ?: @"unknown", (unsigned long)results.count]];

    if (!result) {
        [self logLine:@"Picker cancelled or returned no result."];
        return;
    }

    NSItemProvider *provider = result.itemProvider;
    [self logLine:[NSString stringWithFormat:@"assetIdentifier=%@ registeredTypes=%@", result.assetIdentifier ?: @"(nil)", provider.registeredTypeIdentifiers ?: @[]]];

    self.statusLabel.text = [mode isEqualToString:@"cutout"] ? @"Đang đọc ảnh chủ thể..." : @"Đang đọc hình nền...";
    self.wallpaperButton.enabled = NO;
    self.cutoutButton.enabled = NO;
    self.exportLogButton.enabled = NO;

    NSString *assetIdentifier = result.assetIdentifier;
    void (^finishWithImageData)(NSData *, NSString *, CGImagePropertyOrientation, NSDictionary *) = ^(NSData *imageData, NSString *dataUTI, CGImagePropertyOrientation orientation, NSDictionary *info) {
        BOOL degraded = [info[PHImageResultIsDegradedKey] boolValue];
        BOOL cancelled = [info[PHImageCancelledKey] boolValue];
        NSError *error = info[PHImageErrorKey];
        [self logLine:[NSString stringWithFormat:@"PHImage result: bytes=%lu UTI=%@ orientation=%u degraded=%@ cancelled=%@ error=%@ info=%@", (unsigned long)imageData.length, dataUTI ?: @"(nil)", (unsigned)orientation, degraded ? @"YES" : @"NO", cancelled ? @"YES" : @"NO", error ?: @"(none)", info ?: @{}]];

        if (degraded || cancelled) return;

        dispatch_async(dispatch_get_main_queue(), ^{
            self.wallpaperButton.enabled = YES;
            self.cutoutButton.enabled = YES;
            self.exportLogButton.enabled = YES;

            if (error || imageData.length == 0) {
                NSString *message = error.localizedDescription ?: @"Photos không trả về dữ liệu ảnh.";
                [self logLine:[NSString stringWithFormat:@"PHAsset image-data request failed: %@", message]];
                self.statusLabel.text = [NSString stringWithFormat:@"Không đọc được ảnh: %@", message];
                return;
            }

            UIImage *image = [UIImage imageWithData:imageData scale:1.0];
            if (!image || !image.CGImage) {
                [self logLine:@"UIImage decoding failed even though PHImage returned data."];
                self.statusLabel.text = @"Không giải mã được dữ liệu ảnh.";
                return;
            }

            [self logLine:[NSString stringWithFormat:@"Decoded image: %.0fx%.0f alphaInfo=%d", (CGFloat)CGImageGetWidth(image.CGImage), (CGFloat)CGImageGetHeight(image.CGImage), (int)CGImageGetAlphaInfo(image.CGImage)]];
            [self handleSelectedImage:image data:imageData mode:mode];
        });
    };

    if (assetIdentifier.length > 0) {
        PHAuthorizationStatus auth = [PHPhotoLibrary authorizationStatusForAccessLevel:PHAccessLevelReadWrite];
        [self logLine:[NSString stringWithFormat:@"Photo authorization before asset fetch: %ld", (long)auth]];

        void (^fetchAndRequest)(void) = ^{
            PHFetchResult<PHAsset *> *assets = [PHAsset fetchAssetsWithLocalIdentifiers:@[assetIdentifier] options:nil];
            PHAsset *asset = assets.firstObject;
            if (!asset) {
                [self logLine:@"PHAsset fetch returned no asset."];
                return;
            }

            [self logLine:[NSString stringWithFormat:@"PHAsset found: pixel=%ldx%ld mediaType=%ld subtype=%lu", (long)asset.pixelWidth, (long)asset.pixelHeight, (long)asset.mediaType, (unsigned long)asset.mediaSubtypes]];
            PHImageRequestOptions *options = [[PHImageRequestOptions alloc] init];
            options.version = PHImageRequestOptionsVersionOriginal;
            options.deliveryMode = PHImageRequestOptionsDeliveryModeHighQualityFormat;
            options.resizeMode = PHImageRequestOptionsResizeModeNone;
            options.networkAccessAllowed = YES;

            [[PHImageManager defaultManager] requestImageDataAndOrientationForAsset:asset options:options resultHandler:finishWithImageData];
        };

        if (auth == PHAuthorizationStatusNotDetermined) {
            [self logLine:@"Requesting Photos read/write authorization before PHAsset fetch."];
            [PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelReadWrite handler:^(PHAuthorizationStatus newStatus) {
                [self logLine:[NSString stringWithFormat:@"Photos authorization result: %ld", (long)newStatus]];
                if (newStatus == PHAuthorizationStatusAuthorized || newStatus == PHAuthorizationStatusLimited) {
                    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), fetchAndRequest);
                } else {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        self.wallpaperButton.enabled = YES;
                        self.cutoutButton.enabled = YES;
                        self.exportLogButton.enabled = YES;
                        self.statusLabel.text = @"Chưa được cấp quyền đọc ảnh. Bấm Xuất log (.txt) để xem chi tiết.";
                    });
                }
            }];
        } else if (auth == PHAuthorizationStatusAuthorized || auth == PHAuthorizationStatusLimited) {
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), fetchAndRequest);
        } else {
            [self logLine:@"Photos authorization is denied/restricted; skipping PHAsset path."];
            dispatch_async(dispatch_get_main_queue(), ^{
                self.wallpaperButton.enabled = YES;
                self.cutoutButton.enabled = YES;
                self.exportLogButton.enabled = YES;
                self.statusLabel.text = @"Ứng dụng chưa có quyền đọc ảnh. Hãy cho phép Photos trong Cài đặt rồi thử lại.";
            });
        }
        return;
    }

    [self logLine:@"PHPicker did not provide an assetIdentifier. Falling back to provider loadObjectOfClass:UIImage."];
    [provider loadObjectOfClass:[UIImage class] completionHandler:^(UIImage * _Nullable image, NSError * _Nullable error) {
        [self logLine:[NSString stringWithFormat:@"Provider fallback result: image=%@ errorDomain=%@ code=%ld description=%@ userInfo=%@", image ? @"YES" : @"NO", error.domain ?: @"(nil)", (long)error.code, error.localizedDescription ?: @"(none)", error.userInfo ?: @{}]];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.wallpaperButton.enabled = YES;
            self.cutoutButton.enabled = YES;
            self.exportLogButton.enabled = YES;
            if (!image || !image.CGImage) {
                NSString *message = error.localizedDescription ?: @"Photos không cung cấp ảnh hợp lệ.";
                self.statusLabel.text = [NSString stringWithFormat:@"Không đọc được ảnh: %@", message];
                return;
            }
            NSData *pngData = UIImagePNGRepresentation(image);
            if (!pngData) {
                [self logLine:@"Provider UIImage -> PNG conversion failed."];
                self.statusLabel.text = @"Không thể tạo dữ liệu ảnh.";
                return;
            }
            [self handleSelectedImage:image data:pngData mode:mode];
        });
    }];
}

- (void)handleSelectedImage:(UIImage *)image data:(NSData *)data mode:(NSString *)mode {
    CGSize pixels = CGSizeMake((CGFloat)CGImageGetWidth(image.CGImage), (CGFloat)CGImageGetHeight(image.CGImage));

    if ([mode isEqualToString:@"cutout"] && ![self imageHasAlpha:image.CGImage]) {
        self.statusLabel.text = @"PNG chủ thể phải có nền trong suốt (alpha).";
        return;
    }

    [self ensureSharedDirectoryExists];

    if ([mode isEqualToString:@"wallpaper"]) {
        self.wallpaperPreview = image;
        self.wallpaperPixelSize = pixels;
        self.wallpaperInfoLabel.text = [NSString stringWithFormat:@"Hình nền: %.0f × %.0f px", pixels.width, pixels.height];
        NSData *saveData = data ?: UIImagePNGRepresentation(image);
        if (saveData) [self saveData:saveData toPath:DWWallpaperImagePath];
    } else {
        // A newly selected cutout starts centered; the user can then drag/pinch it.
        self.cutoutNormalizedCenter = CGPointMake(0.5, 0.5);
        self.cutoutScale = 1.0;
        self.cutoutPreview = image;
        self.cutoutPixelSize = pixels;
        self.cutoutInfoLabel.text = [NSString stringWithFormat:@"PNG chủ thể: %.0f × %.0f px", pixels.width, pixels.height];
        NSData *saveData = data ?: UIImagePNGRepresentation(image);
        if (saveData) [self saveData:saveData toPath:DWCutoutImagePath];
    }

    [self updatePreviewAndState];
}

- (BOOL)imageHasAlpha:(CGImageRef)image {
    CGImageAlphaInfo alpha = CGImageGetAlphaInfo(image);
    switch (alpha) {
        case kCGImageAlphaFirst:
        case kCGImageAlphaLast:
        case kCGImageAlphaPremultipliedFirst:
        case kCGImageAlphaPremultipliedLast:
        case kCGImageAlphaOnly:
            return YES;
        default:
            return NO;
    }
}

- (void)updatePreviewAndState {
    if (self.wallpaperPreview && self.cutoutPreview) {
        self.previewBackgroundView.image = [self previewImageForDisplay:self.wallpaperPreview maxPixelSize:1024];
        self.previewCutoutView.image = [self previewImageForDisplay:self.cutoutPreview maxPixelSize:1024];
        self.previewCutoutView.hidden = NO;
        [self applyCutoutTransformAnimated:NO];
        self.statusLabel.text = [NSString stringWithFormat:@"✓ Đã ghép. Nền %.0f×%.0f px • PNG %.0f×%.0f px. Kéo để di chuyển, chụm để zoom.", self.wallpaperPixelSize.width, self.wallpaperPixelSize.height, self.cutoutPixelSize.width, self.cutoutPixelSize.height];
        [self saveMetadataWithAspectMatch:NO];
    } else if (self.wallpaperPreview) {
        self.previewBackgroundView.image = [self previewImageForDisplay:self.wallpaperPreview maxPixelSize:1024];
        self.previewCutoutView.image = nil;
        self.statusLabel.text = @"Đã chọn hình nền. Bây giờ chọn PNG chủ thể đã tách nền.";
    } else if (self.cutoutPreview) {
        self.previewBackgroundView.image = nil;
        self.previewCutoutView.image = [self previewImageForDisplay:self.cutoutPreview maxPixelSize:1024];
        self.statusLabel.text = @"Đã chọn PNG chủ thể. Bạn có thể chọn hình nền với bất kỳ độ phân giải nào.";
    }
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (self.wallpaperPreview && self.cutoutPreview) {
        [self applyCutoutTransformAnimated:NO];
    }
}

- (void)handleCutoutPan:(UIPanGestureRecognizer *)gesture {
    if (!self.cutoutPreview || !self.previewCutoutView.superview) return;
    CGPoint translation = [gesture translationInView:self.previewBackgroundView];
    if (gesture.state == UIGestureRecognizerStateBegan || gesture.state == UIGestureRecognizerStateChanged) {
        CGFloat w = MAX(self.previewBackgroundView.bounds.size.width, 1.0);
        CGFloat h = MAX(self.previewBackgroundView.bounds.size.height, 1.0);
        CGPoint center = self.cutoutNormalizedCenter;
        center.x = MIN(1.5, MAX(-0.5, center.x + translation.x / w));
        center.y = MIN(1.5, MAX(-0.5, center.y + translation.y / h));
        self.cutoutNormalizedCenter = center;
        [gesture setTranslation:CGPointZero inView:self.previewBackgroundView];
        [self applyCutoutTransformAnimated:NO];
    } else if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled) {
        [self persistCutoutTransform];
    }
}

- (void)handleCutoutPinch:(UIPinchGestureRecognizer *)gesture {
    if (!self.cutoutPreview) return;
    if (gesture.state == UIGestureRecognizerStateBegan || gesture.state == UIGestureRecognizerStateChanged) {
        self.cutoutScale *= gesture.scale;
        self.cutoutScale = MIN(4.0, MAX(0.25, self.cutoutScale));
        gesture.scale = 1.0;
        [self applyCutoutTransformAnimated:NO];
    } else if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled) {
        [self persistCutoutTransform];
    }
}

- (void)resetCutoutTransform {
    self.cutoutNormalizedCenter = CGPointMake(0.5, 0.5);
    self.cutoutScale = 1.0;
    [self applyCutoutTransformAnimated:YES];
    [self persistCutoutTransform];
}

- (void)applyCutoutTransformAnimated:(BOOL)animated {
    if (!self.previewCutoutView || self.previewBackgroundView.bounds.size.width <= 0 || self.previewBackgroundView.bounds.size.height <= 0) return;
    CGPoint center = CGPointMake(self.previewBackgroundView.bounds.size.width * self.cutoutNormalizedCenter.x,
                                 self.previewBackgroundView.bounds.size.height * self.cutoutNormalizedCenter.y);
    void (^changes)(void) = ^{
        self.previewCutoutView.center = center;
        self.previewCutoutView.transform = CGAffineTransformMakeScale(self.cutoutScale, self.cutoutScale);
    };
    if (animated) {
        [UIView animateWithDuration:0.18 animations:changes];
    } else {
        changes();
    }
}

- (void)persistCutoutTransform {
    [self saveMetadataWithAspectMatch:NO];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return (gestureRecognizer == self.cutoutPanGesture && otherGestureRecognizer == self.cutoutPinchGesture) ||
           (gestureRecognizer == self.cutoutPinchGesture && otherGestureRecognizer == self.cutoutPanGesture);
}

- (UIImage *)previewImageForDisplay:(UIImage *)image maxPixelSize:(CGFloat)maxPixelSize {
    if (!image.CGImage) return image;
    CGFloat pw = (CGFloat)CGImageGetWidth(image.CGImage);
    CGFloat ph = (CGFloat)CGImageGetHeight(image.CGImage);
    CGFloat longest = MAX(pw, ph);
    if (longest <= maxPixelSize) return image;

    CGFloat ratio = maxPixelSize / longest;
    CGSize size = CGSizeMake(MAX(1.0, floor(pw * ratio)),
                             MAX(1.0, floor(ph * ratio)));
    UIGraphicsBeginImageContextWithOptions(size, NO, 1.0);
    [image drawInRect:(CGRect){CGPointZero, size}];
    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result ?: image;
}

#pragma mark - Persistence

- (void)loadExistingState {
    NSDictionary *meta = [NSDictionary dictionaryWithContentsOfFile:DWMetadataPath];
    self.enabledSwitch.on = meta[DWMetaKeyEnabled] ? [meta[DWMetaKeyEnabled] boolValue] : YES;
    if (meta[DWMetaKeyCutoutCenterX]) self.cutoutNormalizedCenter = CGPointMake([meta[DWMetaKeyCutoutCenterX] doubleValue], self.cutoutNormalizedCenter.y);
    if (meta[DWMetaKeyCutoutCenterY]) self.cutoutNormalizedCenter = CGPointMake(self.cutoutNormalizedCenter.x, [meta[DWMetaKeyCutoutCenterY] doubleValue]);
    if (meta[DWMetaKeyCutoutScale]) self.cutoutScale = MIN(4.0, MAX(0.25, [meta[DWMetaKeyCutoutScale] doubleValue]));

    NSData *bgData = [NSData dataWithContentsOfFile:DWWallpaperImagePath options:NSDataReadingMappedIfSafe error:nil];
    NSData *cutData = [NSData dataWithContentsOfFile:DWCutoutImagePath options:NSDataReadingMappedIfSafe error:nil];
    UIImage *bg = bgData ? [UIImage imageWithData:bgData scale:1.0] : nil;
    UIImage *cut = cutData ? [UIImage imageWithData:cutData scale:1.0] : nil;

    if (bg.CGImage) {
        self.wallpaperPreview = bg;
        self.wallpaperPixelSize = CGSizeMake(CGImageGetWidth(bg.CGImage), CGImageGetHeight(bg.CGImage));
        self.wallpaperInfoLabel.text = [NSString stringWithFormat:@"Hình nền: %.0f × %.0f px", self.wallpaperPixelSize.width, self.wallpaperPixelSize.height];
    }
    if (cut.CGImage) {
        self.cutoutPreview = cut;
        self.cutoutPixelSize = CGSizeMake(CGImageGetWidth(cut.CGImage), CGImageGetHeight(cut.CGImage));
        self.cutoutInfoLabel.text = [NSString stringWithFormat:@"PNG chủ thể: %.0f × %.0f px", self.cutoutPixelSize.width, self.cutoutPixelSize.height];
    }
    [self updatePreviewAndState];
}

- (void)enabledChanged {
    [self saveMetadataWithAspectMatch:CGSizeEqualToSize(self.wallpaperPixelSize, self.cutoutPixelSize)];
}

- (void)saveData:(NSData *)data toPath:(NSString *)path {
    if (!data) return;
    [self ensureSharedDirectoryExists];
    NSError *error = nil;
    BOOL ok = [data writeToFile:path options:NSDataWritingAtomic error:&error];
    [self logLine:[NSString stringWithFormat:@"saveData path=%@ bytes=%lu success=%@ error=%@", path ?: @"(nil)", (unsigned long)data.length, ok ? @"YES" : @"NO", error ?: @"(none)"]];
}

- (void)saveMetadataWithAspectMatch:(BOOL)match {
    [self ensureSharedDirectoryExists];
    NSMutableDictionary *meta = [NSMutableDictionary dictionary];
    meta[DWMetaKeyEnabled] = @(self.enabledSwitch.isOn);
    meta[DWMetaKeyAspectMatch] = @(match);
    meta[DWMetaKeyManualFullResolution] = @YES;
    meta[DWMetaKeyCutoutCenterX] = @(self.cutoutNormalizedCenter.x);
    meta[DWMetaKeyCutoutCenterY] = @(self.cutoutNormalizedCenter.y);
    meta[DWMetaKeyCutoutScale] = @(self.cutoutScale);
    if (!CGSizeEqualToSize(self.wallpaperPixelSize, CGSizeZero)) {
        meta[DWMetaKeyWallpaperWidth] = @(self.wallpaperPixelSize.width);
        meta[DWMetaKeyWallpaperHeight] = @(self.wallpaperPixelSize.height);
    }
    if (!CGSizeEqualToSize(self.cutoutPixelSize, CGSizeZero)) {
        meta[DWMetaKeyCutoutWidth] = @(self.cutoutPixelSize.width);
        meta[DWMetaKeyCutoutHeight] = @(self.cutoutPixelSize.height);
    }
    [meta writeToFile:DWMetadataPath atomically:YES];
    [self notifyTweakToReload];
}

- (void)ensureSharedDirectoryExists {
    [[NSFileManager defaultManager] createDirectoryAtPath:DWSharedDirectory
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
}

- (void)notifyTweakToReload {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                          DWReloadNotification, NULL, NULL, YES);
}

@end
