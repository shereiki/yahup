#ifndef GOOSE_CORE_BRIDGE_H
#define GOOSE_CORE_BRIDGE_H

#ifdef __cplusplus
extern "C" {
#endif

char *goose_core_version_json(void);
char *goose_bridge_handle_json(const char *request_json);
void goose_bridge_free_string(char *value);

#ifdef __cplusplus
}
#endif

#endif
