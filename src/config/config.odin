package config

import "base:runtime"
import "core:encoding/ini"
import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"

// TCP listener config: address, port, connection limit. Defaults to 0.0.0.0:25565.
Server_Config :: struct {
	port:            int,
	address:         string,
	max_connections: int,
}

// Worker thread count for the connection pool. Defaults to 4. Limits how many
// clients can be handled concurrently.
Thread_Pool_Config :: struct {
	max_threads: int,
}

Config :: struct {
	server:      Server_Config,
	thread_pool: Thread_Pool_Config,
}

// Top-level server configuration. Loaded from INI by load/load_with_status;
// falls back to defaults on any error. Destroy via destroy to free string fields.
DEFAULT_SERVER :: Server_Config {
	port            = 25565,
	address         = "0.0.0.0",
	max_connections = 100,
}

DEFAULT_THREAD_POOL :: Thread_Pool_Config {
	max_threads = 4,
}

// Error codes for config loading. Note: load always returns a valid Config
// (with defaults) even on error - use load_with_status to distinguish success
// from fallback.
Config_Error :: enum {
	None,
	File_Open_Failed,
	Parse_Failed,
	Invalid_Value,
}

// Internal: combines a Config with its load error. Exposed by load_with_status;
// the public load proc strips the error and returns a flat (Config, Config_Error).
Config_Load_Result :: struct {
	cfg: Config,
	err: Config_Error,
}

// Loads server config from an INI file. Returns defaults if the file is missing or
// malformed. This is the main public entry point - see load_with_status for details.
load :: proc(allocator: runtime.Allocator, path: string) -> (Config, Config_Error) {
	cfg, err := load_with_status(allocator, path)
	return cfg.cfg, err
}

// Internal: reads and parses the INI file, returning both Config and the error type.
// Logs a warning on failure but always returns a valid Config (with defaults).
load_with_status :: proc(
	allocator: runtime.Allocator,
	path: string,
) -> (
	Config_Load_Result,
	Config_Error,
) {
	data, read_err := os.read_entire_file(path, allocator)
	if read_err != nil {
		fmt.eprintfln("Could not open config file '%s': %v. Using default config.", path, read_err)
		return {cfg = default_config(), err = .None}, .File_Open_Failed
	}
	defer delete(data, allocator)

	src := string(data)
	opts := ini.DEFAULT_OPTIONS
	opts.comment = ";"
	m, ini_err := ini.load_map_from_string(src, allocator, opts)
	if ini_err != nil {
		fmt.eprintfln("Failed to parse config file: %v. Using default config.", ini_err)
		return {cfg = default_config(), err = .Parse_Failed}, .Parse_Failed
	}
	defer ini.delete_map(m)

	cfg := default_config()

	if srv, ok := &m["server"]; ok {
		if v, present := srv["port"]; present {
			if n, ok2 := strconv.parse_int(v, 10); ok2 {
				cfg.server.port = n
			} else {
				fmt.eprintfln("Invalid value for server.port: %q", v)
			}
		}
		if v, present := srv["address"]; present {
			cfg.server.address = strings.clone(v, allocator) or_else DEFAULT_SERVER.address
		}
		if v, present := srv["max_connections"]; present {
			if n, ok2 := strconv.parse_int(v, 10); ok2 {
				cfg.server.max_connections = n
			} else {
				fmt.eprintfln("Invalid value for server.max_connections: %q", v)
			}
		}
	}

	if tp, ok := &m["thread_pool"]; ok {
		if v, present := tp["max_threads"]; present {
			if n, ok2 := strconv.parse_int(v, 10); ok2 {
				cfg.thread_pool.max_threads = n
			} else {
				fmt.eprintfln("Invalid value for thread_pool.max_threads: %q", v)
			}
		}
	}

	return {cfg = cfg, err = .None}, .None
}

// Returns a Config filled with default values (0.0.0.0:25565, 4 pool threads).
default_config :: proc() -> Config {
	return Config{server = DEFAULT_SERVER, thread_pool = DEFAULT_THREAD_POOL}
}

// Frees heap-allocated strings inside a Config (currently just server.address).
destroy :: proc(cfg: Config, allocator: runtime.Allocator) {
	delete(cfg.server.address, allocator)
}
