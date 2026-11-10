/* Fuzzes the parsers for model-generated text: DSML / GLM / Qwen tool-call blocks, reasoning
 * splitting and the truncated-DSML repair. The first input byte selects the model syntax and
 * flags; the rest is the generated text. */
#define main ds4_server_main_not_used
#include "../ds4_server.c"
#undef main

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    if (size < 2) return -1;
    const uint8_t sel = data[0];
    const server_model_syntax syntaxes[] = {
        SERVER_MODEL_SYNTAX_DEEPSEEK, SERVER_MODEL_SYNTAX_GLM,
        SERVER_MODEL_SYNTAX_DEEPSEEK41, SERVER_MODEL_SYNTAX_QWEN,
    };
    const server_model_syntax syntax = syntaxes[sel & 3];
    const bool has_tools = sel & 4;
    const bool saw_tool_start = sel & 8;
    const bool require_thinking_closed = sel & 16;

    char *text = malloc(size);
    if (!text) return 0;
    memcpy(text, data + 1, size - 1);
    text[size - 1] = '\0';

    char err[128] = {0};
    char *content = NULL;
    char *reasoning = NULL;
    tool_calls calls = {0};
    const char *finish = "tool_calls";
    bool recovered = false;
    if (parse_generated_message_for_response_for_syntax(
            syntax, text, has_tools, saw_tool_start, require_thinking_closed,
            &finish, err, sizeof(err), &content, &reasoning, &calls, &recovered,
            NULL)) {
        /* nothing: ownership of content/reasoning/calls is ours either way */
    }
    free(content);
    free(reasoning);
    tool_calls_free(&calls);

    buf repaired = {0};
    if (try_repair_dsml(text, size - 1, &repaired)) {
        char *c2 = NULL, *r2 = NULL;
        tool_calls calls2 = {0};
        (void)parse_generated_message_ex_for_syntax(SERVER_MODEL_SYNTAX_DEEPSEEK, repaired.ptr,
                                                    require_thinking_closed, &c2, &r2, &calls2);
        free(c2);
        free(r2);
        tool_calls_free(&calls2);
    }
    buf_free(&repaired);
    free(text);
    return 0;
}
