#import "ViewController.h"
#import <Vision/Vision.h>
#import <CoreImage/CoreImage.h>
#import "VisionCompat.h"
#import "../DWShared.h"

@interface ViewController ()
@property (nonatomic, strong) UIImageView *previewView;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIButton *pickButton;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) UISlider *yOffsetSlider;
@property (nonatomic, strong) UISlider *scaleSlider;
@property (nonatomic, strong) UISwitch *enabledSwitch;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.view.opaque = YES;
    [self setupUI];
    [self.view setNeedsLayout];
    [self.view layoutIfNeeded];
    [self loadExistingMetadataIntoControls];
}

#pragma mark - Giao dien

- (void)setupUI {
    self.title = @"Depth Wallpaper";

    // Dùng UIScrollView để toàn bộ giao diện luôn dùng được ở cả portrait
    // và landscape, kể cả trên màn hình iPad nhỏ. Các control không bị đẩy
    // xuống ngoài màn hình khi xoay ngang.
    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.alwaysBounceVertical = YES;
    self.scrollView.showsVerticalScrollIndicator = YES;
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.scrollView];

    self.contentView = [[UIView alloc] init];
    self.contentView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scrollView addSubview:self.contentView];

    self.previewView = [[UIImageView alloc] init];
    self.previewView.contentMode = UIViewContentModeScaleAspectFit;
    self.previewView.backgroundColor = [UIColor secondarySystemBackgroundColor];
    self.previewView.layer.cornerRadius = 16;
    self.previewView.clipsToBounds = YES;
    self.previewView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.previewView];

    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.text = @"Chưa có ảnh nào. Chọn một ảnh để tách chủ thể và tạo wallpaper chiều sâu.";
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.font = [UIFont systemFontOfSize:13];
    self.statusLabel.textColor = [UIColor secondaryLabelColor];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.statusLabel];

    self.pickButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.pickButton setTitle:@"Chọn ảnh & Tách nền" forState:UIControlStateNormal];
    self.pickButton.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    self.pickButton.contentEdgeInsets = UIEdgeInsetsMake(12, 20, 12, 20);
    self.pickButton.backgroundColor = [UIColor systemBlueColor];
    [self.pickButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.pickButton.layer.cornerRadius = 12;
    [self.pickButton addTarget:self action:@selector(pickButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    self.pickButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.pickButton];

    UILabel *yLabel = [self makeCaption:@"Vị trí dọc (kéo sang phải = gần đỉnh màn hình hơn)"];
    [self.contentView addSubview:yLabel];
    self.yOffsetSlider = [[UISlider alloc] init];
    self.yOffsetSlider.minimumValue = 0.0;
    self.yOffsetSlider.maximumValue = 0.7;
    self.yOffsetSlider.value = 0.30;
    [self.yOffsetSlider addTarget:self action:@selector(sliderChanged) forControlEvents:UIControlEventValueChanged];
    self.yOffsetSlider.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.yOffsetSlider];

    UILabel *scaleLabel = [self makeCaption:@"Kích thước chủ thể trên màn hình khóa"];
    [self.contentView addSubview:scaleLabel];
    self.scaleSlider = [[UISlider alloc] init];
    self.scaleSlider.minimumValue = 0.4;
    self.scaleSlider.maximumValue = 1.5;
    self.scaleSlider.value = 1.0;
    [self.scaleSlider addTarget:self action:@selector(sliderChanged) forControlEvents:UIControlEventValueChanged];
    self.scaleSlider.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.scaleSlider];

    UILabel *enabledLabel = [self makeCaption:@"Bật hiệu ứng chiều sâu"];
    [self.contentView addSubview:enabledLabel];
    self.enabledSwitch = [[UISwitch alloc] init];
    self.enabledSwitch.on = YES;
    [self.enabledSwitch addTarget:self action:@selector(sliderChanged) forControlEvents:UIControlEventValueChanged];
    self.enabledSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.enabledSwitch];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor],

        // Content width luôn bằng viewport để xoay dọc/ngang không tạo
        // chiều rộng thừa. Chiều cao do Auto Layout + scroll quyết định.
        [self.contentView.leadingAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.leadingAnchor],
        [self.contentView.trailingAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.trailingAnchor],
        [self.contentView.topAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.topAnchor],
        [self.contentView.bottomAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.bottomAnchor],
        [self.contentView.widthAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.widthAnchor],

        // Preview tự co vừa chiều ngang, nhưng không chiếm hết màn hình
        // ở landscape. 4:3 gần với khung ảnh trên iPad và luôn còn chỗ cho nút.
        [self.previewView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:16],
        [self.previewView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:20],
        [self.previewView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-20],
        [self.previewView.heightAnchor constraintEqualToAnchor:self.previewView.widthAnchor multiplier:0.75],
        [self.previewView.heightAnchor constraintLessThanOrEqualToConstant:300],

        [self.statusLabel.topAnchor constraintEqualToAnchor:self.previewView.bottomAnchor constant:12],
        [self.statusLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:20],
        [self.statusLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-20],

        [self.pickButton.topAnchor constraintEqualToAnchor:self.statusLabel.bottomAnchor constant:18],
        [self.pickButton.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
        [self.pickButton.heightAnchor constraintGreaterThanOrEqualToConstant:48],

        [yLabel.topAnchor constraintEqualToAnchor:self.pickButton.bottomAnchor constant:24],
        [yLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:20],
        [yLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-20],
        [self.yOffsetSlider.topAnchor constraintEqualToAnchor:yLabel.bottomAnchor constant:6],
        [self.yOffsetSlider.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:20],
        [self.yOffsetSlider.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-20],

        [scaleLabel.topAnchor constraintEqualToAnchor:self.yOffsetSlider.bottomAnchor constant:18],
        [scaleLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:20],
        [scaleLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-20],
        [self.scaleSlider.topAnchor constraintEqualToAnchor:scaleLabel.bottomAnchor constant:6],
        [self.scaleSlider.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:20],
        [self.scaleSlider.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-20],

        [enabledLabel.topAnchor constraintEqualToAnchor:self.scaleSlider.bottomAnchor constant:18],
        [enabledLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:20],
        [self.enabledSwitch.centerYAnchor constraintEqualToAnchor:enabledLabel.centerYAnchor],
        [self.enabledSwitch.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-20],

        [self.contentView.bottomAnchor constraintGreaterThanOrEqualToAnchor:enabledLabel.bottomAnchor constant:28]
    ]];
}

// Cho cả iPhone/iPad: cho phép xoay tự do giữa portrait và landscape.
- (BOOL)shouldAutorotate {
    return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskAll;
}

- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation {
    return UIInterfaceOrientationPortrait;
}

- (UILabel *)makeCaption:(NSString *)text {
    UILabel *l = [[UILabel alloc] init];
    l.text = text;
    l.font = [UIFont systemFontOfSize:14];
    l.translatesAutoresizingMaskIntoConstraints = NO;
    return l;
}

- (void)loadExistingMetadataIntoControls {
    NSDictionary *meta = [NSDictionary dictionaryWithContentsOfFile:DWMetadataPath];
    if (meta) {
        self.yOffsetSlider.value = meta[DWMetaKeyYOffsetRatio] ? [meta[DWMetaKeyYOffsetRatio] floatValue] : 0.30;
        self.scaleSlider.value = meta[DWMetaKeyScale] ? [meta[DWMetaKeyScale] floatValue] : 1.0;
        self.enabledSwitch.on = meta[DWMetaKeyEnabled] ? [meta[DWMetaKeyEnabled] boolValue] : YES;
    }
    UIImage *cutout = [UIImage imageWithContentsOfFile:DWCutoutImagePath];
    if (cutout) {
        self.previewView.image = cutout;
        self.statusLabel.text = @"Da co anh xu ly tu truoc — chon anh moi de thay doi.";
    }
}

#pragma mark - Chon anh

- (void)pickButtonTapped {
    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    picker.delegate = self;
    picker.allowsEditing = NO;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey,id> *)info {
    [picker dismissViewControllerAnimated:YES completion:nil];
    UIImage *original = info[UIImagePickerControllerOriginalImage];
    if (!original) return;
    [self processImage:original];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Xu ly Vision framework (tach chu the)

- (void)processImage:(UIImage *)sourceImage {
    self.statusLabel.text = @"Dang xu ly... co the mat vai giay tren iPad Air 2 (chip cu).";
    self.pickButton.enabled = NO;

    // Giam kich thuoc truoc khi xu ly de tranh qua tai RAM/CPU tren chip cu (A8X).
    UIImage *resized = [self imageByLimitingLongestSide:sourceImage to:1024];

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *pipelineError = nil;
        BOOL usedPerson = NO;
        UIImage *cutout = [self generateCutoutFromImage:resized
                                  usedPersonSegmentation:&usedPerson
                                                    error:&pipelineError];

        dispatch_async(dispatch_get_main_queue(), ^{
            self.pickButton.enabled = YES;
            if (!cutout) {
                self.statusLabel.text = [NSString stringWithFormat:@"Khong tach duoc chu the: %@",
                                          pipelineError.localizedDescription ?: @"khong ro nguyen nhan"];
                return;
            }
            self.previewView.image = cutout;
            self.statusLabel.text = usedPerson
                ? @"Da tach NGUOI thanh cong. Nho DAT anh GOC nay lam hinh nen khoa may trong Cai dat."
                : @"Khong thay nguoi — da dung do vung noi bat (vd nui/vat cao). Vien co the khong sac net bang truong hop co nguoi.";
            [self saveCutout:cutout];
        });
    });
}

- (UIImage *)imageByLimitingLongestSide:(UIImage *)img to:(CGFloat)maxSide {
    CGFloat longest = MAX(img.size.width, img.size.height);
    if (longest <= maxSide) return img;
    CGFloat scale = maxSide / longest;
    CGSize newSize = CGSizeMake(img.size.width * scale, img.size.height * scale);
    UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat preferredFormat];
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:newSize format:fmt];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [img drawInRect:CGRectMake(0, 0, newSize.width, newSize.height)];
    }];
}

// Tra ve anh cutout (nen trong suot, chi giu chu the) hoac nil neu that bai.
// Thu NGUOI truoc (chinh xac hon nhieu, API chinh thuc tu iOS 15), khong co
// nguoi thi roi xuong saliency (do vung noi bat — cho vat the nhu nui, toa nha
// cao, do vat noi bat khac). Day la 2 API CONG KHAI cua Apple, khong phai
// private — do tin cay cao hon nhieu so voi cac phan private khac trong tweak.
- (UIImage *)generateCutoutFromImage:(UIImage *)image
              usedPersonSegmentation:(BOOL *)outUsedPerson
                                error:(NSError **)outError {
    CIImage *ciImage = [[CIImage alloc] initWithImage:image];
    if (!ciImage) {
        if (outError) *outError = [NSError errorWithDomain:@"DepthWallpaper" code:1
                                                    userInfo:@{NSLocalizedDescriptionKey: @"Khong doc duoc anh"}];
        return nil;
    }

    VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCIImage:ciImage options:@{}];

    // --- Buoc 1: thu nhan dien NGUOI ---
    // Dung NSClassFromString thay vi viet thang ten class — vi SDK 14.5 dung de
    // build (tranh loi parse header cua toolchain) khong co THU VIEN LIEN KET
    // (linking stub) cho class nay (chi moi co tu SDK iOS 15). Viet thang ten
    // class se khien "ld" bao loi "symbol not found" luc lien ket. Lay class
    // qua ten chuoi thi khong can trinh lien ket biet truoc — luc chay that tren
    // may iOS 15+ van tim thay va goi dung class that cua he thong.
    Class personReqClass = NSClassFromString(@"VNGeneratePersonSegmentationRequest");
    if (personReqClass) {
        id personReq = [[personReqClass alloc] init];
        // Dung cu phap ngoac (khong phai dot-syntax) vi personReq duoc khai bao
        // kieu "id" — dot-syntax can biet kieu tinh, ngoac thi khong can.
        [personReq setQualityLevel:VNGeneratePersonSegmentationRequestQualityLevelAccurate];
        [personReq setOutputPixelFormat:kCVPixelFormatType_OneComponent8];

        NSError *err1 = nil;
        [handler performRequests:@[personReq] error:&err1];
        VNPixelBufferObservation *firstObs = [[personReq results] firstObject];
        CVPixelBufferRef maskBuf = firstObs.pixelBuffer;

        if (maskBuf && [self maskHasReasonableCoverage:maskBuf]) {
            if (outUsedPerson) *outUsedPerson = YES;
            return [self compositeImage:ciImage withMask:maskBuf softenEdge:2.0];
        }
    }

    // --- Buoc 2: fallback — do vung noi bat nhat trong anh ---
    VNGenerateObjectnessBasedSaliencyImageRequest *salReq = [[VNGenerateObjectnessBasedSaliencyImageRequest alloc] init];
    NSError *err2 = nil;
    [handler performRequests:@[salReq] error:&err2];
    VNSaliencyImageObservation *obs = salReq.results.firstObject;

    if (!obs || !obs.pixelBuffer) {
        if (outError) *outError = err2 ?: [NSError errorWithDomain:@"DepthWallpaper" code:2
                                                            userInfo:@{NSLocalizedDescriptionKey: @"Khong tim thay chu the noi bat nao trong anh"}];
        return nil;
    }

    if (outUsedPerson) *outUsedPerson = NO;
    // Saliency map thuong co do phan giai rat thap va it sac net — lam mem vien
    // nhieu hon (sigma lon hon) de tranh rang cua kho thay.
    return [self compositeImage:ciImage withMask:obs.pixelBuffer softenEdge:6.0];
}

- (BOOL)maskHasReasonableCoverage:(CVPixelBufferRef)maskBuffer {
    CIImage *maskCI = [CIImage imageWithCVPixelBuffer:maskBuffer];
    CIContext *ctx = [CIContext contextWithOptions:nil];
    CIImage *avgImg = [maskCI imageByApplyingFilter:@"CIAreaAverage"
                                  withInputParameters:@{kCIInputExtentKey: [CIVector vectorWithCGRect:maskCI.extent]}];
    uint8_t bitmap[4] = {0, 0, 0, 0};
    [ctx render:avgImg toBitmap:bitmap rowBytes:4 bounds:CGRectMake(0, 0, 1, 1) format:kCIFormatRGBA8 colorSpace:nil];
    CGFloat avgBrightness = bitmap[0] / 255.0;
    return avgBrightness > 0.015; // nguong rat thap, chi loai truong hop mask hoan toan rong (khong co nguoi)
}

- (UIImage *)compositeImage:(CIImage *)sourceCI withMask:(CVPixelBufferRef)maskBuffer softenEdge:(CGFloat)sigma {
    CIImage *maskCI = [CIImage imageWithCVPixelBuffer:maskBuffer];

    CGFloat sx = sourceCI.extent.size.width / MAX(maskCI.extent.size.width, 1);
    CGFloat sy = sourceCI.extent.size.height / MAX(maskCI.extent.size.height, 1);
    CIImage *scaledMask = [maskCI imageByApplyingTransform:CGAffineTransformMakeScale(sx, sy)];
    if (sigma > 0) {
        scaledMask = [scaledMask imageByApplyingGaussianBlurWithSigma:sigma];
    }

    CIFilter *blend = [CIFilter filterWithName:@"CIBlendWithMask"];
    [blend setValue:sourceCI forKey:kCIInputImageKey];
    [blend setValue:[CIImage imageWithColor:[CIColor colorWithRed:0 green:0 blue:0 alpha:0]] forKey:kCIInputBackgroundImageKey];
    [blend setValue:scaledMask forKey:kCIInputMaskImageKey];
    CIImage *result = blend.outputImage;
    result = [result imageByCroppingToRect:sourceCI.extent];

    CIContext *ctx = [CIContext contextWithOptions:nil];
    CGImageRef cgImg = [ctx createCGImage:result fromRect:result.extent];
    if (!cgImg) return nil;
    UIImage *img = [UIImage imageWithCGImage:cgImg];
    CGImageRelease(cgImg);
    return img;
}

#pragma mark - Luu ket qua ra thu muc dung chung (de Tweak.x doc duoc)

- (void)sliderChanged {
    [self saveMetadataOnly];
}

- (void)saveMetadataOnly {
    NSMutableDictionary *meta = [NSMutableDictionary dictionary];
    meta[DWMetaKeyYOffsetRatio] = @(self.yOffsetSlider.value);
    meta[DWMetaKeyScale] = @(self.scaleSlider.value);
    meta[DWMetaKeyEnabled] = @(self.enabledSwitch.isOn);
    [self ensureSharedDirectoryExists];
    [meta writeToFile:DWMetadataPath atomically:YES];
    [self notifyTweakToReload];
}

- (void)saveCutout:(UIImage *)cutout {
    [self ensureSharedDirectoryExists];
    NSData *pngData = UIImagePNGRepresentation(cutout);
    [pngData writeToFile:DWCutoutImagePath atomically:YES];
    [self saveMetadataOnly]; // luu luon vi tri/kich thuoc hien tai cung luc
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
