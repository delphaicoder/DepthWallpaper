#import "ViewController.h"
#import <PhotosUI/PhotosUI.h>
#import "../DWShared.h"

@interface ViewController () <PHPickerViewControllerDelegate>
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) UIImageView *previewBackgroundView;
@property (nonatomic, strong) UIImageView *previewCutoutView;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIButton *wallpaperButton;
@property (nonatomic, strong) UIButton *cutoutButton;
@property (nonatomic, strong) UISwitch *enabledSwitch;
@property (nonatomic, strong) UILabel *wallpaperInfoLabel;
@property (nonatomic, strong) UILabel *cutoutInfoLabel;
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

    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.font = [UIFont systemFontOfSize:14.0];
    self.statusLabel.textColor = UIColor.secondaryLabelColor;
    self.statusLabel.text = @"Chọn hình nền gốc và PNG đã tách nền. Hai ảnh phải cùng kích thước pixel.";
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

        [enabledLabel.topAnchor constraintEqualToAnchor:self.cutoutInfoLabel.bottomAnchor constant:18],
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
    PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:configuration];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    [picker dismissViewControllerAnimated:YES completion:nil];
    PHPickerResult *result = results.firstObject;
    if (!result) return;

    NSItemProvider *provider = result.itemProvider;
    NSString *mode = [self.pickerMode copy];
    self.statusLabel.text = [mode isEqualToString:@"cutout"] ? @"Đang đọc ảnh chủ thể..." : @"Đang đọc hình nền...";
    self.wallpaperButton.enabled = NO;
    self.cutoutButton.enabled = NO;

    // Do not request public.png directly. On iOS 15 Photos providers can
    // advertise an image as PNG while refusing that exact representation.
    // public.image is much more widely supported. We still validate alpha
    // for the cutout after decoding the image.
    NSString *identifier = @"public.image";

    [provider loadDataRepresentationForTypeIdentifier:identifier
                                    completionHandler:^(NSData *data, NSError *error) {
        UIImage *image = data ? [UIImage imageWithData:data scale:1.0] : nil;

        // Some providers don't vend data even though they can vend UIImage.
        // Fall back to loadObject rather than failing the picker operation.
        if (!image || !image.CGImage) {
            [provider loadObjectOfClass:[UIImage class]
                      completionHandler:^(UIImage *fallbackImage, NSError *fallbackError) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.wallpaperButton.enabled = YES;
                    self.cutoutButton.enabled = YES;

                    if (!fallbackImage || !fallbackImage.CGImage) {
                        NSString *message = fallbackError.localizedDescription ?: error.localizedDescription ?: @"Photos không cung cấp dữ liệu ảnh hợp lệ.";
                        self.statusLabel.text = [NSString stringWithFormat:@"Không đọc được ảnh: %@", message];
                        return;
                    }

                    NSData *fallbackData = UIImagePNGRepresentation(fallbackImage);
                    [self handleSelectedImage:fallbackImage data:fallbackData mode:mode];
                });
            }];
            return;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            self.wallpaperButton.enabled = YES;
            self.cutoutButton.enabled = YES;
            [self handleSelectedImage:image data:data mode:mode];
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
        self.wallpaperInfoLabel.text = [NSString stringWithFormat:@"Hình nền: %.0f × %.0f px — giữ nguyên", pixels.width, pixels.height];
        NSData *saveData = data ?: UIImagePNGRepresentation(image);
        if (saveData) [self saveData:saveData toPath:DWWallpaperImagePath];
    } else {
        self.cutoutPreview = image;
        self.cutoutPixelSize = pixels;
        self.cutoutInfoLabel.text = [NSString stringWithFormat:@"PNG chủ thể: %.0f × %.0f px — giữ nguyên", pixels.width, pixels.height];
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
        BOOL sameSize = CGSizeEqualToSize(self.wallpaperPixelSize, self.cutoutPixelSize);
        if (!sameSize) {
            self.previewCutoutView.image = nil;
            self.previewBackgroundView.image = self.wallpaperPreview;
            self.statusLabel.text = [NSString stringWithFormat:@"⚠️ Không khớp kích thước. Nền: %.0f×%.0f — PNG: %.0f×%.0f. Hãy chọn 2 ảnh cùng pixel.", self.wallpaperPixelSize.width, self.wallpaperPixelSize.height, self.cutoutPixelSize.width, self.cutoutPixelSize.height];
            [self saveMetadataWithAspectMatch:NO];
            return;
        }

        self.previewBackgroundView.image = [self previewImageForDisplay:self.wallpaperPreview maxPixelSize:1024];
        self.previewCutoutView.image = [self previewImageForDisplay:self.cutoutPreview maxPixelSize:1024];
        self.statusLabel.text = [NSString stringWithFormat:@"✓ Khớp %.0f × %.0f px. Không resize file gốc — preview giảm riêng để tiết kiệm RAM.", self.wallpaperPixelSize.width, self.wallpaperPixelSize.height];
        [self saveMetadataWithAspectMatch:YES];
    } else if (self.wallpaperPreview) {
        self.previewBackgroundView.image = self.wallpaperPreview;
        self.previewCutoutView.image = nil;
        self.statusLabel.text = @"Đã chọn hình nền. Bây giờ chọn PNG chủ thể cùng kích thước pixel.";
    } else if (self.cutoutPreview) {
        self.previewBackgroundView.image = nil;
        self.previewCutoutView.image = self.cutoutPreview;
        self.statusLabel.text = @"Đã chọn PNG chủ thể. Bây giờ chọn hình nền cùng kích thước pixel.";
    }
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

    NSData *bgData = [NSData dataWithContentsOfFile:DWWallpaperImagePath options:NSDataReadingMappedIfSafe error:nil];
    NSData *cutData = [NSData dataWithContentsOfFile:DWCutoutImagePath options:NSDataReadingMappedIfSafe error:nil];
    UIImage *bg = bgData ? [UIImage imageWithData:bgData scale:1.0] : nil;
    UIImage *cut = cutData ? [UIImage imageWithData:cutData scale:1.0] : nil;

    if (bg.CGImage) {
        self.wallpaperPreview = bg;
        self.wallpaperPixelSize = CGSizeMake(CGImageGetWidth(bg.CGImage), CGImageGetHeight(bg.CGImage));
        self.wallpaperInfoLabel.text = [NSString stringWithFormat:@"Hình nền: %.0f × %.0f px — giữ nguyên", self.wallpaperPixelSize.width, self.wallpaperPixelSize.height];
    }
    if (cut.CGImage) {
        self.cutoutPreview = cut;
        self.cutoutPixelSize = CGSizeMake(CGImageGetWidth(cut.CGImage), CGImageGetHeight(cut.CGImage));
        self.cutoutInfoLabel.text = [NSString stringWithFormat:@"PNG chủ thể: %.0f × %.0f px — giữ nguyên", self.cutoutPixelSize.width, self.cutoutPixelSize.height];
    }
    [self updatePreviewAndState];
}

- (void)enabledChanged {
    [self saveMetadataWithAspectMatch:CGSizeEqualToSize(self.wallpaperPixelSize, self.cutoutPixelSize)];
}

- (void)saveData:(NSData *)data toPath:(NSString *)path {
    if (!data) return;
    [self ensureSharedDirectoryExists];
    [data writeToFile:path options:NSDataWritingAtomic error:nil];
}

- (void)saveMetadataWithAspectMatch:(BOOL)match {
    [self ensureSharedDirectoryExists];
    NSMutableDictionary *meta = [NSMutableDictionary dictionary];
    meta[DWMetaKeyEnabled] = @(self.enabledSwitch.isOn);
    meta[DWMetaKeyAspectMatch] = @(match);
    meta[DWMetaKeyManualFullResolution] = @YES;
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
