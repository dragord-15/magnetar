// demo_vision.mg - Camera + object detection demo for Magnetar (robot vision)
// Build: ./magc examples/demo_vision.mg -o build/demo_vision
// Run:   ./build/demo_vision [device] [color]
//   device: camera device (default: /dev/video0)
//   color : red | green | blue | rgb (default: blue)
//
// What it does:
//   - Captures one frame from camera via ffmpeg/V4L2 (PPM)
//   - Detects colored objects (blobs) and prints their bbox/center/area
//   - Prints robot steering hint for the largest object (-100 left .. 100 right)
//   - Saves annotated frame to /tmp/mg_vision_out.ppm
//
// Requirements: ffmpeg installed and a working /dev/videoX camera.

use "lib/image.mg";
use "lib/vision.mg";

extern fn print_str(string s) -> void;

fn main(int argc, char** argv) -> int {
    string dev = "/dev/video0";
    string mode = "blue";

    if (argc > 1) { dev = cast<string>(argv[1]); }
    if (argc > 2) { mode = cast<string>(argv[2]); }

    print_str("Magnetar Vision Demo\n");
    print_str("Device: "); print_str(dev); print_str("\n");

    if (vision_camera_available(dev) == false) {
        print_str("Camera device not found.\n");
        return 1;
    }
    if (vision_ffmpeg_available() == false) {
        print_str("ffmpeg not found (needed for camera capture).\n");
        return 1;
    }

    int w = 320;
    int h = 240;
    print_str("Capturing frame...\n");
    Image* frame = vision_grab_frame(dev, w, h);
    if (frame == null) {
        print_str("Failed to capture/load frame.\n");
        return 1;
    }
    print_str("Frame: "); print(frame.width); print_str("x"); print(frame.height); print_str("\n");

    VisionResult res;
    vision_result_init(&res, 16);

    int found = 0;
    int ann_r = 0; int ann_g = 255; int ann_b = 0;

    // mode selection by first char
    char* mp = cast<char*>(mode);
    int m0 = cast<int>(*mp);
    if (m0 < 0) { m0 = m0 + 256; }

    if (m0 == 114) { // 'r' red
        found = vision_detect_red(frame, 60, &res);
        ann_r = 255; ann_g = 80; ann_b = 80;
    } else if (m0 == 103) { // 'g' green
        found = vision_detect_green(frame, 60, &res);
        ann_r = 80; ann_g = 255; ann_b = 80;
    } else if (m0 == 98) { // 'b' blue
        found = vision_detect_blue(frame, 60, &res);
        ann_r = 80; ann_g = 180; ann_b = 255;
    } else {
        // rgb demo: detect bright saturated-ish blue range via RGB thresholds
        found = vision_detect_rgb_range(frame, 0, 0, 120, 120, 140, 255, 60, 3, &res);
        ann_r = 255; ann_g = 255; ann_b = 0;
    }

    vision_result_info(&res);

    if (res.count > 0) {
        int bi = vision_find_largest(&res);
        VisionObject obj = vision_get_object(&res, bi);
        int steer = vision_object_steer_x(obj, frame.width);
        int ratio = vision_object_area_ratio(obj, frame.width, frame.height);
        print_str("Largest: id="); print(obj.id);
        print_str(" center=("); print(obj.cx); print_str(","); print(obj.cy); print_str(")");
        print_str(" steer="); print(steer);
        print_str(" area_permille="); print(ratio);
        print_str("\n");

        if (steer < -15) {
            print_str("Robot hint: TURN LEFT\n");
        } else if (steer > 15) {
            print_str("Robot hint: TURN RIGHT\n");
        } else {
            if (ratio < 120) {
                print_str("Robot hint: MOVE FORWARD\n");
            } else {
                print_str("Robot hint: TARGET REACHED / STOP\n");
            }
        }
    } else {
        print_str("No object detected. Try: ./build/demo_vision /dev/video0 red|green|blue\n");
    }

    vision_draw_objects(frame, &res, ann_r, ann_g, ann_b);
    if (image_save_ppm(frame, "/tmp/mg_vision_out.ppm") == true) {
        print_str("Annotated frame saved: /tmp/mg_vision_out.ppm\n");
    }

    vision_result_free(&res);
    image_destroy(frame);
    return 0;
}
