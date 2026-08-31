//
//  VisionCompat.h
//  Khai bao bo sung cho Vision.framework — SDK 14.5 (dung de tranh loi parse
//  header cua toolchain Linux, xem du an LiquidFolder truoc do) khong co khai
//  bao VNGeneratePersonSegmentationRequest vi API nay chi xuat hien tu SDK iOS
//  15 tro len. Class NAY VAN TON TAI THAT SU tren may chay iOS 15+ (duoc nap
//  luc runtime tu Vision.framework that cua he thong) — chi la SDK dung de bien
//  dich khong "biet" ve no. Tu khai bao lai dung interface de trinh bien dich
//  chiu, luc chay thuc te van goi dung ham that cua he thong, khong anh huong gi.
//
#ifndef VisionCompat_h
#define VisionCompat_h

#import <Vision/Vision.h>

API_AVAILABLE(ios(15.0))
typedef NS_ENUM(NSInteger, VNGeneratePersonSegmentationRequestQualityLevel) {
    VNGeneratePersonSegmentationRequestQualityLevelAccurate = 0,
    VNGeneratePersonSegmentationRequestQualityLevelBalanced = 1,
    VNGeneratePersonSegmentationRequestQualityLevelFast = 2,
};

API_AVAILABLE(ios(15.0))
@interface VNGeneratePersonSegmentationRequest : VNImageBasedRequest
@property (nonatomic, assign) VNGeneratePersonSegmentationRequestQualityLevel qualityLevel;
@property (nonatomic, assign) OSType outputPixelFormat;
@property (nonatomic, readonly, copy) NSArray<VNPixelBufferObservation *> *results;
@end

#endif /* VisionCompat_h */
