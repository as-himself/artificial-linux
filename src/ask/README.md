# ask - SLM gateway binary

C++ client that sends prompts to the local llama-server and prints the completion.

- **ask.cpp**: Uses libcurl for HTTP; manual JSON escaping and response parsing (no JSON library required).
- **json.hpp**: Not used by default. For full JSON handling you can add [nlohmann/json](https://github.com/nlohmann/json) single-header as `json.hpp` and link if needed.
- **Build**: `cmake -B build -DCMAKE_INSTALL_PREFIX=/usr/local && cmake --build build && cmake --install build` (requires libcurl-dev).
