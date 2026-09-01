# DepthWallpaper — Hiệu ứng "chiều sâu" kiểu iOS 16 cho màn hình khoá iPad

**[THỬ NGHIỆM]** Mô phỏng tính năng "Depth Effect" của iOS 16 (chủ thể ảnh nổi
phía trước đồng hồ khoá màn hình) — vốn iPadOS không có tính năng này.

## 1. Gồm 2 phần

- **DepthWallpaperApp** — app nhỏ để bạn chọn ảnh, dùng Vision framework của
  Apple tự tách chủ thể (người hoặc vật nổi bật) ra khỏi nền, lưu kết quả.
- **DepthWallpaperTweak** — chạy trong SpringBoard, chỉ đọc ảnh đã tách và
  hiện nó **đè lên trên** đồng hồ khoá máy khi máy đang khoá.

Cả 2 đóng gói chung trong 1 file `.deb`, cài 1 lần là có cả app lẫn tweak.

## 2. Cách dùng

1. Cài `.deb`, mở app **DepthWallpaper**.
2. Bấm **"Chọn ảnh & tách chủ thể"**, chọn 1 ảnh từ thư viện.
3. Đợi vài giây (chip A8X xử lý AI khá chậm) — ảnh đã tách chủ thể sẽ hiện ra.
4. Chỉnh 2 thanh trượt nếu cần: **Vị trí dọc** (chủ thể cao/thấp) và **Kích
   thước**.
5. **Quan trọng**: vào **Cài đặt > Hình nền**, đặt **CHÍNH ảnh gốc** này (chưa
   qua xử lý) làm hình nền **màn hình khoá**.
6. Khoá máy để xem hiệu ứng.

## 3. Vì sao cần đặt ảnh nền thủ công (bước 5)?

Bạn đã chọn phương án an toàn hơn ở bước hỏi trước — tweak **không tự đọc**
ảnh nền hệ thống (tránh phải đoán API riêng tư). Overlay chủ thể chỉ đè lên
**đúng ảnh bạn đã đặt làm hình nền**, nên 2 bước (đặt hình nền qua Cài đặt +
chọn ảnh trong app) cần dùng **cùng 1 ảnh** để khớp nhau.

## 4. Cơ chế "chiều sâu" hoạt động thế nào

Không hề "di chuyển" hay "sửa" đồng hồ thật của hệ thống. Chỉ đơn giản là xếp
lớp (z-order): overlay chứa ảnh chủ thể (nền trong suốt) được đặt ở tầng cửa
sổ **cao hơn** tầng vẽ đồng hồ khoá máy. Chỗ nào chủ thể che lên đồng hồ, phần
đó tự nhiên bị khuất — đúng bản chất cách tính năng thật của Apple hoạt động.

## 5. Độ tin cậy từng phần (đọc để biết nên tin đến đâu)

| Phần | Kỹ thuật | Độ tin cậy |
|---|---|---|
| Tách người trong ảnh | `VNGeneratePersonSegmentationRequest` (API công khai, chính thức từ iOS 15) | **Cao** |
| Tách vật thể nổi bật (núi...) | `VNGenerateObjectnessBasedSaliencyImageRequest` (API công khai từ iOS 13, nhưng thô hơn nhiều — không có API "tách vật thể chung" xịn như iOS 17+) | **Trung bình** — viền không sắc nét |
| Phát hiện máy đang khoá | `UIApplication.isProtectedDataAvailable` (API công khai, chính thức) | **Cao** |
| Vị trí overlay khớp với hình nền thật | Tính toán hình học đơn giản, giả định bạn không zoom/kéo ảnh khi đặt làm hình nền | **Trung bình** — có thể lệch nếu bạn chỉnh ảnh khi đặt hình nền |

So với các tweak trước (DynamicIsland, AppOpenAnimation...), phần lõi ở đây
**đáng tin cậy hơn hẳn** vì hầu hết dùng API công khai, không phải đoán private.

## 6. Cấu trúc project
```
DepthWallpaper/
├── control
├── Makefile                      # build ca app va tweak
├── DWShared.h                     # hang so dung chung (duong dan, key)
├── DepthWallpaperTweak.plist      # filter: chi SpringBoard
├── Tweak.x                        # phan SpringBoard (hien overlay)
├── DepthWallpaperApp/
│   ├── main.m / AppDelegate.h+m
│   ├── ViewController.h+m         # UI chon anh + toan bo xu ly Vision framework
│   └── Resources/Info.plist
└── .github/workflows/build.yml
```

## 7. Build & cài đặt
Quy trình giống các tweak trước: tạo repo GitHub mới, upload nội dung thư mục
này, tab Actions tự build trên Linux, tải `.deb`, cài qua Sileo.

## 8. Nếu muốn chỉnh sau này
- Đổi vị trí/kích thước mặc định: sửa `value` mặc định của 2 slider trong
  `ViewController.m` (`yOffsetSlider`/`scaleSlider`).
- Đổi ngưỡng nhận diện người (nếu hay bị rơi xuống fallback saliency dù ảnh có
  người): chỉnh số `0.015` trong `maskHasReasonableCoverage:`.
- Không có Settings.app riêng (theo đúng thói quen các tweak trước — tránh rủi
  ro) — mọi chỉnh sửa làm ngay trong app đi kèm.

## 9. Bản 1.0.1 — sửa lỗi app không xuất hiện

Bản này đặt app tại `/Applications/DepthWallpaper.app` (Theos rootless sẽ đóng gói dưới `/var/jb/Applications/`) và chạy `uicache` sau khi cài để LaunchServices đăng ký app. Đồng thời đã thêm bộ icon PNG và `CFBundleIcons` vào Info.plist. Theos rootless dùng `/var/jb/` làm install prefix và đặt architecture gói là `iphoneos-arm64`. 
