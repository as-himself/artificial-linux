/*
 * Artificial Linux - ask: C++ gateway to SLM inference server
 * Queries llama-server via HTTP, returns completion text. Used by shell and scripts.
 */
#include <iostream>
#include <string>
#include <sstream>
#include <iomanip>
#include <curl/curl.h>
#include <cstdlib>
#include <cstring>

#ifndef ASK_CONF
#define ASK_CONF "/etc/ai-fabric/ask.conf"
#endif
#ifndef ASK_DEFAULT_URL
#define ASK_DEFAULT_URL "http://127.0.0.1:8080"
#endif
#ifndef ASK_DEFAULT_TIMEOUT
#define ASK_DEFAULT_TIMEOUT 120
#endif

static size_t WriteCallback(void* contents, size_t size, size_t nmemb, std::string* out) {
    size_t total = size * nmemb;
    out->append(static_cast<char*>(contents), total);
    return total;
}

static std::string escape_json(const std::string& s) {
    std::ostringstream o;
    for (char c : s) {
        switch (c) {
            case '"':  o << "\\\""; break;
            case '\\': o << "\\\\"; break;
            case '\b': o << "\\b"; break;
            case '\f': o << "\\f"; break;
            case '\n': o << "\\n"; break;
            case '\r': o << "\\r"; break;
            case '\t': o << "\\t"; break;
            default:
                if (static_cast<unsigned char>(c) < 0x20)
                    o << "\\u" << std::hex << std::setfill('0') << std::setw(4) << static_cast<unsigned>(c);
                else
                    o << c;
        }
    }
    return o.str();
}

int main(int argc, char* argv[]) {
    if (argc < 2) {
        std::cerr << "Usage: ask \"<prompt>\" [n_predict]\n";
        return 1;
    }

    std::string prompt = argv[1];
    int n_predict = 128;
    if (argc >= 3) n_predict = std::atoi(argv[2]);
    if (n_predict <= 0) n_predict = 128;

    std::string url = ASK_DEFAULT_URL;
    long timeout = ASK_DEFAULT_TIMEOUT;
    const char* env_url = std::getenv("ASK_URL");
    if (env_url) url = env_url;
    const char* env_to = std::getenv("ASK_TIMEOUT");
    if (env_to) timeout = std::strtol(env_to, nullptr, 10);
    if (timeout <= 0) timeout = ASK_DEFAULT_TIMEOUT;

    std::string endpoint = url;
    if (endpoint.back() != '/') endpoint += '/';
    endpoint += "completion";

    std::string json = "{\"prompt\":\"" + escape_json(prompt) + "\",\"n_predict\":";
    json += std::to_string(n_predict);
    json += ",\"stream\":false}";

    std::string response;
    CURL* curl = curl_easy_init();
    if (!curl) {
        std::cerr << "ask: curl init failed\n";
        return 1;
    }

    curl_easy_setopt(curl, CURLOPT_URL, endpoint.c_str());
    curl_easy_setopt(curl, CURLOPT_POSTFIELDS, json.c_str());
    curl_easy_setopt(curl, CURLOPT_POST, 1L);
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, WriteCallback);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, &response);
    curl_easy_setopt(curl, CURLOPT_TIMEOUT, timeout);
    curl_easy_setopt(curl, CURLOPT_HTTPHEADER, curl_slist_append(nullptr, "Content-Type: application/json"));

    CURLcode res = curl_easy_perform(curl);
    curl_easy_cleanup(curl);

    if (res != CURLE_OK) {
        std::cerr << "ask: " << curl_easy_strerror(res) << "\n";
        return 1;
    }

    /* Simple extraction of "content" from JSON (no full parser required for minimal build) */
    size_t pos = response.find("\"content\":\"");
    if (pos != std::string::npos) {
        pos += 10;
        size_t end = pos;
        while (end < response.size()) {
            if (response[end] == '\\' && end + 1 < response.size()) { end += 2; continue; }
            if (response[end] == '"') break;
            end++;
        }
        std::string content = response.substr(pos, end - pos);
        for (size_t i = 0; i < content.size(); ) {
            if (content[i] == '\\' && i + 1 < content.size()) {
                switch (content[i+1]) {
                    case 'n': std::cout << '\n'; break;
                    case 't': std::cout << '\t'; break;
                    case 'r': std::cout << '\r'; break;
                    case '"': std::cout << '"'; break;
                    case '\\': std::cout << '\\'; break;
                    default: std::cout << content[i+1]; break;
                }
                i += 2;
            } else {
                std::cout << content[i];
                i++;
            }
        }
    } else {
        std::cout << response;
    }
    std::cout << std::endl;
    return 0;
}
