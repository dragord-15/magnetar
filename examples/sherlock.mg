// ============================================================================
// Magnetar Sherlock - username reconnaissance over public websites
// File: examples/sherlock.mg
//
// A small, ethical OSINT helper inspired by sherlock-project. It checks a
// username against a list of public profile URLs and prints the HTTP result.
//
// Build:  ./magc examples/sherlock.mg -o sherlock
// Run:    ./sherlock
//
// Change the USERNAME constant below, or set it from your own UI/bot code.
// Only check accounts you own or have permission to investigate.
// ============================================================================

use "http.mg";
use "url.mg";
use "console.mg";
extern fn print_str(string s) -> void;

fn sherlock_verdict(int status) -> string {
    if (status == 200) { return "FOUND"; }
    if (status == 301 || status == 302 || status == 303 || status == 307 || status == 308) {
        return "REDIRECT";
    }
    if (status == 403 || status == 429) { return "BLOCKED/RATE-LIMITED"; }
    if (status == 404) { return "NOT FOUND"; }
    if (status == -1) { return "NETWORK ERROR"; }
    return "UNKNOWN";
}

fn sherlock_check(string template, string username, string user_agent) -> int {
    string encoded = url_encode_form_component(username);
    string target = str_replace(template, "{u}", encoded);
    string headers = str_concat("User-Agent: ", str_concat(user_agent, "\r\n"));
    headers = str_concat(headers, "Accept: text/html,application/xhtml+xml\r\n");
    return http_probe_ex(target, headers, 8000);
}

fn sherlock_print_image_search(string image_url) -> void {
    string encoded = url_encode_form_component(image_url);
    print_str("[image] Google Lens : https://lens.google.com/uploadbyurl?url=");
    print_str(encoded);
    print_str("\n[image] Yandex      : https://yandex.com/images/search?rpt=imageview&url=");
    print_str(encoded);
    print_str("\n[image] Bing Visual : https://www.bing.com/images/search?view=detailv2&iss=sbi&form=SBIVSP&q=imgurl:");
    print_str(encoded);
    print_str("\n[image] TinEye      : https://tineye.com/search?url=");
    print_str(encoded);
    print_str("\n");
}

fn main() -> int {
    string username = input("\n username: ");
    string user_agent = "Mozilla/5.0 (X11; Linux x86_64) MagnetarSherlock/1.0";

    string site_names[16];
    string site_templates[16];

    site_names[0] = "GitHub";       site_templates[0] = "https://github.com/{u}";
    site_names[1] = "GitLab";       site_templates[1] = "https://gitlab.com/{u}";
    site_names[2] = "Reddit";       site_templates[2] = "https://www.reddit.com/user/{u}";
    site_names[3] = "Instagram";    site_templates[3] = "https://www.instagram.com/{u}/";
    site_names[4] = "X (Twitter)";  site_templates[4] = "https://x.com/{u}";
    site_names[5] = "TikTok";       site_templates[5] = "https://www.tiktok.com/@{u}";
    site_names[6] = "Pinterest";    site_templates[6] = "https://www.pinterest.com/{u}/";
    site_names[7] = "Telegram";     site_templates[7] = "https://t.me/{u}";
    site_names[8] = "PyPI";         site_templates[8] = "https://pypi.org/user/{u}/";
    site_names[9] = "npm";          site_templates[9] = "https://www.npmjs.com/~{u}";
    site_names[10] = "Keybase";     site_templates[10] = "https://keybase.io/{u}";
    site_names[11] = "Twitch";      site_templates[11] = "https://www.twitch.tv/{u}";
    site_names[12] = "Medium";      site_templates[12] = "https://medium.com/@{u}";
    site_names[13] = "Docker Hub";  site_templates[13] = "https://hub.docker.com/u/{u}";
    site_names[14] = "Hacker News"; site_templates[14] = "https://news.ycombinator.com/user?id={u}";
    site_names[15] = "Dev.to";      site_templates[15] = "https://dev.to/{u}";

    print_str("==============================================================\n");
    print_str(" Magnetar Sherlock - public username reconnaissance\n");
    print_str("==============================================================\n");
    print_str("Target username: ");
    print_str(username);
    print_str("\n\n");

    int found = 0;
    for (int i = 0; i < 16; i = i + 1) {
        int status = sherlock_check(site_templates[i], username, user_agent);
        string verdict = sherlock_verdict(status);
        if (status == 200) { found = found + 1; }

        print_str("[");
        if (status == 200) { print_green("+"); } else { print_red("?"); }
        print_str("] ");
        print(site_names[i],"   ->  ");
        //print_str(" -> ");
        print_str(verdict);
        print_str(" (HTTP ");
        print(status);
        print_str(")\n");

        time_sleep_ms(350);
    }

    print_str("\nProfiles with HTTP 200: ");
    print(found);
    print_str("\n\n");

    print_str("Reverse image search links (replace the sample URL):\n");
    sherlock_print_image_search("https://example.com/avatar.png");
    return 0;
}
