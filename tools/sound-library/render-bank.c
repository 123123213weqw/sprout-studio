#include <stdlib.h>
#define TSF_IMPLEMENTATION
#include "tsf.h"
static tsf *bank;
int open_bank(const char *path) { bank=tsf_load_filename(path); if(!bank)return 0; tsf_set_output(bank,TSF_MONO,44100,0); tsf_set_max_voices(bank,64); return tsf_get_presetcount(bank); }
const char *preset_name(int program) { int index=tsf_get_presetindex(bank,0,program); return index<0?NULL:tsf_get_presetname(bank,index); }
int render_note(int program,int pitch,int velocity,float *out,int frames) { float clear[4096];int index=tsf_get_presetindex(bank,0,program);if(index<0||pitch<0||pitch>127||velocity<1||velocity>127||frames<1)return 0;tsf_reset(bank);tsf_render_float(bank,clear,4096,0);if(!tsf_note_on(bank,index,pitch,velocity/127.0f))return 0;tsf_render_float(bank,out,frames,0);return 1; }
void close_bank(void) { tsf_close(bank);bank=NULL; }
