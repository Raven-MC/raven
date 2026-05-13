package config

import "base:runtime"
import "core:encoding/ini"
import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"

Server_Config :: struct {
	port:            int,
	address:         string,
	max_connections: int,
}

Thread_Pool_Config :: struct {
	max_threads: int,
}

Config :: struct {
	server:     Server_Config,
	thread_pool: Thread_Pool_Config,
}

DEFAULT_SERVER :: Server_Config {
	port            = 25565,
	address         = "0.0.0.0",
	max_connections = 100,
}

DEFAULT_THREAD_POOL :: Thread_Pool_Config {
	max_threads = 4,
}

Config_Error :: enum {
	None,
	File_Open_Failed,
	Parse_Failed,
	Invalid_Value,
}

Config_Load_Result :: struct {
	cfg: Config,
	err: Config_Error,
}

load :: proc(allocator: runtime.Allocator, path: string) -> (Config, runtime.Allocator_Error) {
	cfg, err := load_with_status(allocator, path)
	return cfg.cfg, err == .None ? nil : .None
}

load_with_status :: proc(allocator: runtime.Allocator, path: string) -> (Config_Load_Result, Config_Error) {
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

default_config :: proc() -> Config {
	return Config {
		server      = DEFAULT_SERVER,
		thread_pool = DEFAULT_THREAD_POOL,
	}
}

destroy :: proc(cfg: Config, allocator: runtime.Allocator) {
	delete(cfg.server.address, allocator)
}
