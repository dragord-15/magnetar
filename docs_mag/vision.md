# Magnetar Vision Library (`lib/vision.mg`)

Camera capture and simple color/object detection helpers for small robots.

## Dependencies
- `use "lib/image.mg";` then `use "lib/vision.mg";`
- Camera capture uses external **`ffmpeg`** with V4L2 (`/dev/videoX`)

## Quick example
```mg
use "lib/image.mg";
use "lib/vision.mg";

fn main() -> int {
    VisionResult res;
    vision_result_init(&res, 16);

    Image* frame = vision_grab_frame("/dev/video0", 320, 240);
    if (frame != null) {
        int n = vision_detect_blue(frame, 80, &res);
        if (n > 0) {
            int bi = vision_find_largest(&res);
            VisionObject obj = vision_get_object(&res, bi);
            int steer = vision_object_steer_x(obj, frame.width); // -100..100
            int near  = vision_object_area_ratio(obj, frame.width, frame.height); // permille
            vision_draw_objects(frame, &res, 0, 255, 0);
            image_save_ppm(frame, "/tmp/vision_out.ppm");
        }
        image_destroy(frame);
    }
    vision_result_free(&res);
    return 0;
}
```

## Capture
- `vision_camera_available(string device) -> bool` - checks `/dev/videoX` exists.
- `vision_ffmpeg_available() -> bool` - checks for ffmpeg.
- `vision_capture(string device, int w, int h, string out_path) -> bool` - grabs 1 frame to PPM.
- `vision_grab_frame(string device, int w, int h) -> Image*` - capture + load (caller must `image_destroy`).

## Detection
Results are stored in `VisionResult` (parallel arrays). Always `vision_result_init(&res, capacity)` before use and `vision_result_free(&res)` when done.

- `vision_detect_rgb_range(Image* img, rmin,gmin,bmin,rmax,gmax,bmax, min_area, label, VisionResult* res) -> int`
- `vision_detect_hsv_range(Image* img, hmin,smin,vmin,hmax,smax,vmax, min_area, label, VisionResult* res) -> int` (H: 0..360, S/V: 0..100; supports hue wrap when `hmin > hmax`)
- Presets: `vision_detect_red/green/blue(Image*, min_area, VisionResult*) -> int` (labels 1=red,2=green,3=blue)

## Reading results
- `res.count` - number of detected blobs.
- `vision_get_object(VisionResult* res, int i) -> VisionObject` - fields: `id,label,x,y,w,h,cx,cy,area,r,g,b`.
- `vision_find_largest(VisionResult* res) -> int` - index of largest blob (-1 if none).
- `vision_result_info(VisionResult* res)` - print detections.

## Robot helpers
- `vision_object_steer_x(obj, img_w) -> int` - horizontal error: -100 (left) .. 100 (right).
- `vision_object_steer_y(obj, img_h) -> int` - vertical error.
- `vision_object_area_ratio(obj, img_w, img_h) -> int` - object area in permille of frame (proxy for distance/size).

## Motion detection
Frame differencing: only pixels that changed since the previous frame are reported, so stationary objects are ignored.

- `vision_motion_init(VisionMotion* m, int w, int h, int threshold)` - prepare storage (threshold is the sum of per-channel absolute differences, default ~30).
- `vision_motion_detect(VisionMotion* m, Image* img, int min_area, VisionResult* res) -> int` - fill `res` with blobs (label 5). First call only captures the reference frame.
- `vision_motion_reset(VisionMotion* m)` - discard the reference frame (use after reconnect/camera change).
- `vision_motion_free(VisionMotion* m)` - release storage.

## Annotation
- `vision_draw_object(Image*, VisionObject, r,g,b)` / `vision_draw_objects(Image*, VisionResult*, r,g,b)` - draw bbox + center cross.

## Demo
```bash
./magc examples/demo_vision.mg -o build/demo_vision
./build/demo_vision /dev/video0 blue   # or red|green|rgb
# saves annotated frame to /tmp/mg_vision_out.ppm
```

Notes: color/blob detection works best with distinct colored targets/markers and consistent lighting. Keep frames small (e.g. 160x120–320x240) for responsiveness on small robots.
