use "lib/image.mg";

fn main() {
    int w = 256;
    int h = 256;
    Image* img = image_new(w, h);
    if (img == null) {
        print_str("Could not create image\n");
        return;
    }

    for (int y = 0; y < h; y = y + 1) {
        for (int x = 0; x < w; x = x + 1) {
            image_set_pixel(img, x, y, x, y, (x + y) / 2, 255);
        }
    }

    image_fill_circle(img, 64, 64, 36, 255, 255, 255, 255);
    image_draw_rect(img, 120, 40, 96, 72, 255, 128, 0, 255);
    image_draw_line(img, 0, 255, 255, 0, 0, 0, 0, 255);
    image_draw_circle(img, 160, 170, 56, 255, 0, 128, 255);

    if (!image_save(img, "image_demo.png")) {
        print_str("Could not save image_demo.png\n");
        image_destroy(img);
        return;
    }
    if (!image_save_thumbnail(img, "image_demo_thumb.png", 96)) {
        print_str("Could not save thumbnail\n");
    }

    Image* gray = image_clone(img);
    if (gray != null) {
        image_grayscale(gray);
        image_save(gray, "image_demo_gray.png");
        image_destroy(gray);
    }

    Image* flipped = image_flip_horizontal(img);
    if (flipped != null) {
        image_save(flipped, "image_demo_flipped.png");
        image_destroy(flipped);
    }

    image_destroy(img);

    Image* loaded = image_load("image_demo.png");
    if (loaded != null) {
        image_print_info(loaded);
        image_destroy(loaded);
    }
    print_str("Image demo complete\n");
}
