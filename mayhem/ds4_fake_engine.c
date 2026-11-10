/* The fuzz build's ds4.o: upstream's ds4.c plus a model-less engine for the server request
 * parsers, which only need the (empty) vocab to tokenize rendered prompts. */
#include "../ds4.c"

ds4_engine *mayhem_fake_engine(void) {
    static ds4_engine *e;
    if (!e) {
        e = calloc(1, sizeof(*e));
        if (!e) abort();
        int *ids[] = {
            &e->vocab.bos_id, &e->vocab.eos_id, &e->vocab.system_id, &e->vocab.user_id,
            &e->vocab.assistant_id, &e->vocab.observation_id, &e->vocab.sop_id,
            &e->vocab.think_start_id, &e->vocab.think_end_id, &e->vocab.tool_call_start_id,
            &e->vocab.tool_call_end_id, &e->vocab.tool_response_start_id,
            &e->vocab.tool_response_end_id, &e->vocab.arg_key_start_id, &e->vocab.arg_key_end_id,
            &e->vocab.arg_value_start_id, &e->vocab.arg_value_end_id, &e->vocab.dsml_id,
            &e->vocab.im_start_id, &e->vocab.im_end_id, &e->vocab.endoftext_id,
        };
        for (size_t i = 0; i < sizeof(ids) / sizeof(ids[0]); i++) *ids[i] = (int)i + 1;
    }
    return e;
}
