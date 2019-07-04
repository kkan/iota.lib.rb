#include <ruby.h>
#include <stdint.h>

#define HASH_LENGTH 243
#define NUMBER_OF_ROUNDS 81
#define STATE_LENGTH 3 * HASH_LENGTH

typedef int64_t trit_t;

#define __TRUTH_TABLE 1,  0, -1, 1, -1,  0, -1,  1,  0

static const trit_t TRUTH_TABLE[9] = {__TRUTH_TABLE};

typedef struct {
  int rounds;
  trit_t state[STATE_LENGTH];
} Curl;

static VALUE ccurl_transform(VALUE self);

static VALUE ccurl_alloc(VALUE klass) {
  Curl *ctx = ALLOC(Curl);
  return Data_Wrap_Struct(klass, 0, RUBY_DEFAULT_FREE, ctx);
}

static VALUE ccurl_init(VALUE self, VALUE rounds) {
  Curl *ctx;
  int requested = NUMBER_OF_ROUNDS;

  if (TYPE(rounds) != T_NIL) {
    requested =  NUM2INT(rounds);
  }

  Data_Get_Struct(self, Curl, ctx);

  ctx->rounds = requested;
  memset(ctx->state, (trit_t)0, STATE_LENGTH * sizeof(trit_t));

  return self;
}

static VALUE ccurl_absorb(VALUE self, VALUE data) {
  trit_t *trits;
  int offset = 0;
  int i;
  int length = NUM2INT(rb_funcall(data, rb_intern("length"), 0, 0));

  Curl *ctx;
  Data_Get_Struct(self, Curl, ctx);

  trits = (trit_t*)malloc(length * sizeof(trit_t));

  for (i = 0; i < length; ++i) {
    trits[i] = (trit_t)(NUM2LONG(rb_ary_entry(data, i)));
  }

  do {
    memcpy(ctx->state, trits + offset, (length < HASH_LENGTH ? length : HASH_LENGTH) * sizeof(trit_t));
    ccurl_transform(self);
    offset += HASH_LENGTH;
  } while ((length -= HASH_LENGTH) > 0);

  free(trits);

  return Qnil;
}

static VALUE ccurl_squeeze(VALUE self, VALUE data) {
  int offset = 0;
  int i;
  int length = NUM2INT(rb_funcall(data, rb_intern("length"), 0, 0));

  Curl *ctx;
  Data_Get_Struct(self, Curl, ctx);

  do {
    for(; length < HASH_LENGTH; length++) {
      rb_ary_push(data, LONG2NUM(0));
    }

    for (i = 0; i < HASH_LENGTH; i++) {
      rb_ary_store(data, i, LONG2NUM(ctx->state[i]));
    }

    ccurl_transform(self);
    offset += HASH_LENGTH;
  } while ((length -= HASH_LENGTH) > 0);

  return Qnil;
}

static VALUE ccurl_transform(VALUE self) {
  trit_t scratchpad[STATE_LENGTH];
  int round, scratchpadIndex=0, scratchpadIndexSave, stateIndex;

  Curl *ctx;
  Data_Get_Struct(self, Curl, ctx);

  for (round = 0; round < NUMBER_OF_ROUNDS; round++) {
    memcpy(scratchpad, ctx->state, STATE_LENGTH * sizeof(trit_t));

    for (stateIndex = 0; stateIndex < STATE_LENGTH; stateIndex++) {
      scratchpadIndexSave = scratchpadIndex;
      scratchpadIndex += (scratchpadIndex < 365 ? 364 : -365);
      ctx->state[stateIndex] = TRUTH_TABLE[scratchpad[scratchpadIndexSave ] + scratchpad[scratchpadIndex ] * 3 + 4];
    }
  }

  return Qnil;
}

static VALUE ccurl_reset(VALUE self) {
  Curl *ctx;
  Data_Get_Struct(self, Curl, ctx);
  memset(ctx->state, 0, STATE_LENGTH * sizeof(char));
  return Qnil;
}

void Init_ccurl(void) {
  VALUE iota = rb_define_module("IOTA");
  VALUE iotaCrypto = rb_define_module_under(iota, "Crypto");
  VALUE cCurl = rb_define_class_under(iotaCrypto, "CCurl", rb_cObject);

  rb_define_alloc_func(cCurl, ccurl_alloc);
  rb_define_method(cCurl, "initialize", ccurl_init, 1);
  rb_define_method(cCurl, "absorb", ccurl_absorb, 1);
  rb_define_method(cCurl, "squeeze", ccurl_squeeze, 1);
  rb_define_method(cCurl, "transform", ccurl_transform, 0);
  rb_define_method(cCurl, "reset", ccurl_reset, 0);
}
