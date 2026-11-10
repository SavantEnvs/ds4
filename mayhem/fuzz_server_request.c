/* Fuzzes the HTTP request-body parsers of ds4-server (chat, anthropic, responses, completion
 * request JSON, plus the JSON tool-argument helpers). The first input byte selects the entry
 * point; the rest is the body. ds4_server.c is included so its static parsers are reachable;
 * its main() is renamed away. The engine is a model-less stub (mayhem/ds4_fake_engine.c, empty vocab); the
 * server object is NULL, which the parsers accept. */
#define main ds4_server_main_not_used
#include "../ds4_server.c"
#undef main

extern ds4_engine *mayhem_fake_engine(void);

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    if (size < 2) return -1;
    const unsigned mode = data[0] % 5;
    char *body = malloc(size);
    if (!body) return 0;
    memcpy(body, data + 1, size - 1);
    body[size - 1] = '\0';

    ds4_engine *eng = mayhem_fake_engine();
    char err[160];
    request r;
    bool ok = false;
    switch (mode) {
    case 0: ok = parse_chat_request(eng, NULL, body, 64, 4096, &r, err, sizeof(err)); break;
    case 1: ok = parse_anthropic_request(eng, NULL, body, 64, 4096, &r, err, sizeof(err)); break;
    case 2: ok = parse_responses_request(eng, NULL, body, 64, 4096, &r, err, sizeof(err)); break;
    case 3: ok = parse_completion_request(eng, body, 64, 4096, &r, err, sizeof(err)); break;
    default: {
        json_args args = {0};
        if (json_args_parse(body, &args)) {
            for (int i = 0; i < args.len; i++) (void)json_args_find_unused(&args, args.v[i].key);
        }
        json_args_free(&args);
        char *min = json_minify_raw_value(body);
        free(min);
        break;
    }
    }
    if (mode < 4 && ok) request_free(&r);
    free(body);
    return 0;
}
