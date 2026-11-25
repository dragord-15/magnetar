// ============================================================================
// Magnetar Standard Library: LLM & Generative AI Integration (lib/llm.mg)
//
// Connects Magnetar directly to Real Generative AI & Large Language Models:
//   - Google Gemini API (gemini-1.5-flash / gemini-2.0-flash)
//   - Groq API (Llama 3.3 70B, Mixtral)
//   - Pollinations AI (Free Public AI - No Key Required!)
//   - Ollama (Local LLM on localhost:11434 without any API keys or internet)
//
// Pure Magnetar implementation over the native HTTP/TLS stack.
// ============================================================================

use "lib/http.mg";
use "lib/string.mg";
use "lib/buffer.mg";

// ============================================================================
// 1. Google Gemini API Provider (100% Free with Google Account)
// ============================================================================

fn llm_gemini_generate(string api_key, string model, string system_prompt, string user_prompt, int max_tokens) -> string {
    if (api_key == null || len(api_key) == 0) {
        return "⚠️ لم يتم تزويد مفتاح Google Gemini API! يرجى تعيين المفتاح في الكود.";
    }

    // Validate that key is actually a Google API key (starts with AIzaSy)
    if (!str_starts_with(api_key, "AIzaSy")) {
        return "⚠️ المفتاح الذي وضعته ليس مفتاح Google Gemini!\nمفاتيح Gemini تبدأ بـ: AIzaSy...\n\nيمكنك الحصول على مفتاح Gemini مجاناً 100% بدون أي بطاقة بنكية من:\nhttps://aistudio.google.com/app/apikey";
    }

    if (model == null || len(model) == 0) {
        model = "gemini-1.5-flash";
    }
    if (max_tokens <= 0) { max_tokens = 800; }

    // Combine system prompt and user prompt
    string full_prompt = user_prompt;
    if (len(system_prompt) > 0) {
        full_prompt = str_concat(system_prompt, str_concat("\n\nUser: ", user_prompt));
    }

    // Build Gemini JSON body
    StringBuilder sb;
    sb.init(1024);
    sb.append("{\"contents\":[{\"parts\":[{\"text\":\"");
    sb.append(http_json_escape(full_prompt));
    sb.append("\"}]}],\"generationConfig\":{\"temperature\":0.7,\"maxOutputTokens\":");
    sb.append(int_to_str(max_tokens));
    sb.append("}}");
    string body = sb.to_string();
    sb.free_builder();

    string url = str_concat("https://generativelanguage.googleapis.com/v1beta/models/",
                 str_concat(model, str_concat(":generateContent?key=", api_key)));

    HttpResponse resp = http_request_ex("POST", url, body, "application/json", "", true, 30000, true);

    if (resp.error != "") {
        return str_concat("⚠️ خطأ في الاتصال بنموذج الذكاء الاصطناعي: ", resp.error);
    }

    if (resp.status_code != 200) {
        string err_msg = http_json_get_string(resp.body, "message");
        if (len(err_msg) == 0) { err_msg = resp.body; }
        return str_concat("⚠️ خطأ من خادم الذكاء الاصطناعي: ", err_msg);
    }

    string generated_text = http_json_get_string(resp.body, "text");
    if (len(generated_text) == 0) {
        return "لم أستطع صياغة إجابة مناسبة في الوقت الحالي. هل يمكنك إعادة صياغة السؤال؟";
    }

    return generated_text;
}

// ============================================================================
// 2. Groq / OpenAI-compatible API Provider (100% Free at console.groq.com)
// ============================================================================

fn llm_groq_generate(string api_key, string model, string system_prompt, string user_prompt, int max_tokens) -> string {
    if (api_key == null || len(api_key) == 0) {
        return "⚠️ لم يتم تزويد مفتاح Groq API! يرجى تعيين المفتاح في الكود.";
    }
    if (model == null || len(model) == 0) {
        model = "openai/gpt-oss-120b";
    }
    if (max_tokens <= 0) { max_tokens = 800; }

    StringBuilder sb;
    sb.init(1024);
    sb.append("{\"model\":\"");
    sb.append(model);
    sb.append("\",\"messages\":[");
    if (len(system_prompt) > 0) {
        sb.append("{\"role\":\"system\",\"content\":\"");
        sb.append(http_json_escape(system_prompt));
        sb.append("\"},");
    }
    sb.append("{\"role\":\"user\",\"content\":\"");
    sb.append(http_json_escape(user_prompt));
    sb.append("\"}],\"temperature\":0.7,\"max_tokens\":");
    sb.append(int_to_str(max_tokens));
    sb.append("}");
    string body = sb.to_string();
    sb.free_builder();

    string url = "https://api.groq.com/openai/v1/chat/completions";
    string auth_header = str_concat("Authorization: Bearer ", api_key);

    HttpResponse resp = http_request_ex("POST", url, body, "application/json", auth_header, true, 30000, true);

    if (resp.error != "") {
        return str_concat("⚠️ خطأ في الاتصال بـ Groq: ", resp.error);
    }

    if (resp.status_code != 200) {
        string err_msg = http_json_get_string(resp.body, "message");
        if (len(err_msg) == 0) { err_msg = resp.body; }
        return str_concat("⚠️ خطأ من Groq API: ", err_msg);
    }

    string generated_text = http_json_get_string(resp.body, "content");
    if (len(generated_text) == 0) {
        return "عذراً، لم أستطع توليد إجابة.";
    }

    return generated_text;
}

// ============================================================================
// 3. Pollinations AI (Free Public AI - No Key Required!)
// ============================================================================

fn llm_pollinations_generate(string system_prompt, string user_prompt) -> string {
    StringBuilder sb;
    sb.init(1024);
    sb.append("{\"messages\":[");
    if (len(system_prompt) > 0) {
        sb.append("{\"role\":\"system\",\"content\":\"");
        sb.append(http_json_escape(system_prompt));
        sb.append("\"},");
    }
    sb.append("{\"role\":\"user\",\"content\":\"");
    sb.append(http_json_escape(user_prompt));
    sb.append("\"}],\"model\":\"openai\"}");
    string body = sb.to_string();
    sb.free_builder();

    string url = "https://text.pollinations.ai/";
    HttpResponse resp = http_request_ex("POST", url, body, "application/json", "", true, 35000, true);

    if (resp.error != "" || resp.status_code != 200) {
        return "";
    }

    // Check if rate limited
    if (str_contains(resp.body, "Free limit reached")) {
        return "";
    }

    return resp.body;
}

// ============================================================================
// 4. Ollama (Local AI on machine without any API keys or internet)
// ============================================================================

fn llm_ollama_generate(string model, string prompt) -> string {
    if (model == null || len(model) == 0) {
        model = "llama3";
    }

    StringBuilder sb;
    sb.init(512);
    sb.append("{\"model\":\"");
    sb.append(model);
    sb.append("\",\"prompt\":\"");
    sb.append(http_json_escape(prompt));
    sb.append("\",\"stream\":false}");
    string body = sb.to_string();
    sb.free_builder();

    string url = "http://localhost:11434/api/generate";
    HttpResponse resp = http_post_json(url, body);

    if (resp.error != "") {
        return "⚠️ خادم Ollama المحلي غير مشغل! يمكنك تشغيله بأمر: ollama run llama3";
    }

    return http_json_get_string(resp.body, "response");
}
