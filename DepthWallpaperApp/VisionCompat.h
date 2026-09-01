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
//  LUU Y: trong ViewController.m, class nay duoc lay qua NSClassFromString (KHONG
//  viet thang ten class trong code thuc thi) vi SDK 14.5 cung KHONG co thu vien
//  lien ket (linking stub) cho class nay — viet thang ten se gay loi "symbol not
//  found" luc lien ket (linker), khac voi loi "undeclared identifier" luc bien
//  dich (compiler) ma file nay giai quyet. Xem chi tiet trong ViewController.m.
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
