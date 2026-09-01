#import "ViewController.h"
#import <PhotosUI/PhotosUI.h>
#import <ImageIO/ImageIO.h>
#import "../DWShared.h"

@interface ViewController () <PHPickerViewControllerDelegate>
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) UIImageView *previewView;
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

- (UIButton *)makeButtonWithTitle:(NSString *)title action:(SEL)action;
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

    self.previewView = [[UIImageView alloc] init];
    self.previewView.translatesAutoresizingMaskIntoConstraints = NO;
    self.previewView.backgroundColor = UIColor.secondarySystemBackgroundColor;
    self.previewView.layer.cornerRadius = 16.0;
    self.previewView.clipsToBounds = YES;
    self.previewView.contentMode = UIViewContentModeScaleAspectFit;
    [self.contentView addSubview:self.previewView];

    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.font = [UIFont systemFontOfSize:14.0];
    self.statusLabel.textColor = UIColor.secondaryLabelColor;
    self.statusLabel.text = @"Chọn 2 ảnh cùng độ phân giải: hình nền gốc + PNG đã tách nền. App sẽ giữ nguyên kích thước, không resize chủ thể.";
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

        [self.previewView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:16],
        [self.previewView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:20],
        [self.previewView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-20],
        [self.previewView.heightAnchor constraintEqualToAnchor:self.previewView.widthAnchor multiplier:0.5625],
        [self.previewView.heightAnchor constraintLessThanOrEqualToConstant:360],

        [self.statusLabel.topAnchor constraintEqualToAnchor:self.previewView.bottomAnchor constant:12],
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

#pragma mark - Picker

- (void)selectWallpaper {
    self.pickerMode = @"wallpaper";
    [self presentPickerAllowMultiple:NO];
}

- (void)selectCutout {
    self.pickerMode = @"cutout";
    [self presentPickerAllowMultiple:NO];
}

- (void)presentPickerAllowMultiple:(BOOL)allowMultiple {
    PHPickerConfiguration *configuration = [[PHPickerConfiguration alloc] initWithPhotoLibrary:PHPhotoLibrary.sharedPhotoLibrary];
    configuration.filter = [PHPickerFilter imagesFilter];
    configuration.selectionLimit = allowMultiple ? 0 : 1;
    PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:configuration];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    [picker dismissViewControllerAnimated:YES completion:nil];
    PHPickerResult *result = results.firstObject;
    if (!result) return;

    NSItemProvider *provider = result.itemProvider;
    self.statusLabel.text = @"Đang đọc ảnh gốc, không resize...";
    self.wallpaperButton.enabled = NO;
    self.cutoutButton.enabled = NO;

    // Prefer the original file representation so pixel dimensions/alpha and
    // the cutout PNG are preserved instead of being recompressed through UIImage.
    NSString *typeIdentifier = nil;
    if ([self.pickerMode isEqualToString:@"cutout"]) {
        typeIdentifier = @"public.png";
    } else {
        typeIdentifier = @"public.image";
    }

    [provider loadFileRepresentationForTypeIdentifier:typeIdentifier completionHandler:^(NSURL * _Nullable url, NSError * _Nullable error) {
        if (!url) {
            // Fallback to decoded UIImage when Photos does not offer a file representation.
            [provider loadObjectOfClass:[UIImage class] completionHandler:^(UIImage * _Nullable image, NSError * _Nullable imageError) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.wallpaperButton.enabled = YES;
                    self.cutoutButton.enabled = YES;
                    if (image) {
                        [self handleImage:image mode:self.pickerMode originalData:nil typeIdentifier:typeIdentifier];
                    } else {
                        self.statusLabel.text = [NSString stringWithFormat:@"Không đọc được ảnh: %@", imageError.localizedDescription ?: error.localizedDescription ?: @"unknown"];
                    }
                });
            }];
            return;
        }

        NSData *data = [NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.wallpaperButton.enabled = YES;
            self.cutoutButton.enabled = YES;
            if (!data) {
                self.statusLabel.text = @"Không đọc được file ảnh gốc.";
                return;
            }
            UIImage *image = [UIImage imageWithData:data scale:1.0];
            [self handleImage:image mode:self.pickerMode originalData:data typeIdentifier:typeIdentifier];
        });
    }];
}

#pragma mark - Pair processing (NO Vision / NO resize)

- (void)handleImage:(UIImage *)image mode:(NSString *)mode originalData:(NSData *)originalData typeIdentifier:(NSString *)typeIdentifier {
    if (!image || !image.CGImage) {
        self.statusLabel.text = @"Ảnh không có CGImage hợp lệ.";
        return;
    }

    CGSize pixels = CGSizeMake(CGImageGetWidth(image.CGImage), CGImageGetHeight(image.CGImage));

    if ([mode isEqualToString:@"cutout"] && ![self imageHasAlpha:image.CGImage]) {
        self.statusLabel.text = @"Ảnh chủ thể phải là PNG có nền trong suốt (alpha).";
        return;
    }

    if ([mode isEqualToString:@"wallpaper"]) {
        self.wallpaperPreview = image;
        self.wallpaperPixelSize = pixels;
        self.wallpaperInfoLabel.text = [NSString stringWithFormat:@"Hình nền: %.0f × %.0f px — giữ nguyên", pixels.width, pixels.height];
        if (originalData) {
            [self saveData:originalData toPath:DWWallpaperImagePath];
        } else {
            NSData *png = UIImagePNGRepresentation(image);
            if (png) [self saveData:png toPath:DWWallpaperImagePath];
        }
    } else {
        // The selected PNG is stored byte-for-byte when Photos provides the
        // original file. No crop, resize or re-encoding of the cutout.
        self.cutoutPreview = image;
        self.cutoutPixelSize = pixels;
        self.cutoutInfoLabel.text = [NSString stringWithFormat:@"Chủ thể: %.0f × %.0f px — giữ nguyên", pixels.width, pixels.height];
        if (originalData) {
            [self saveData:originalData toPath:DWCutoutImagePath];
        } else {
            NSData *png = UIImagePNGRepresentation(image);
            if (png) [self saveData:png toPath:DWCutoutImagePath];
        }
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
            self.statusLabel.text = [NSString stringWithFormat:@"⚠️ Không khớp kích thước. Nền: %.0f×%.0f — Chủ thể: %.0f×%.0f. Hãy chọn lại 2 ảnh cùng pixel.", self.wallpaperPixelSize.width, self.wallpaperPixelSize.height, self.cutoutPixelSize.width, self.cutoutPixelSize.height];
            self.previewView.image = self.wallpaperPreview;
            [self saveMetadataWithAspectMatch:NO];
            return;
        }

        self.previewView.image = [self compositePreviewWithBackground:self.wallpaperPreview cutout:self.cutoutPreview];
        self.statusLabel.text = [NSString stringWithFormat:@"✓ Hai ảnh khớp %.0f × %.0f px. Không resize — PNG chủ thể được giữ nguyên.", self.wallpaperPixelSize.width, self.wallpaperPixelSize.height];
        [self saveMetadataWithAspectMatch:YES];
    } else if (self.wallpaperPreview) {
        self.previewView.image = self.wallpaperPreview;
        self.statusLabel.text = @"Đã chọn hình nền. Bây giờ chọn PNG chủ thể đã tách nền.";
    } else if (self.cutoutPreview) {
        self.previewView.image = self.cutoutPreview;
        self.statusLabel.text = @"Đã chọn PNG chủ thể. Bây giờ chọn hình nền gốc cùng độ phân giải.";
    }
}

- (UIImage *)compositePreviewWithBackground:(UIImage *)background cutout:(UIImage *)cutout {
    CGSize size = background.size;
    UIGraphicsBeginImageContextWithOptions(size, YES, 1.0);
    [background drawInRect:(CGRect){CGPointZero, size}];
    [cutout drawInRect:(CGRect){CGPointZero, size}];
    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result;
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
        self.cutoutInfoLabel.text = [NSString stringWithFormat:@"Chủ thể: %.0f × %.0f px — giữ nguyên", self.cutoutPixelSize.width, self.cutoutPixelSize.height];
    }
    [self updatePreviewAndState];
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

- (void)enabledChanged {
    [self saveMetadataWithAspectMatch:CGSizeEqualToSize(self.wallpaperPixelSize, self.cutoutPixelSize)];
}

- (void)ensureSharedDirectoryExists {
    [[NSFileManager defaultManager] createDirectoryAtPath:DWSharedDirectory withIntermediateDirectories:YES attributes:nil error:nil];
}

- (void)notifyTweakToReload {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), DWReloadNotification, NULL, NULL, YES);
}

@end
