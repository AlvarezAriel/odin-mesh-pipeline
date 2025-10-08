package main

import MTL "vendor:darwin/Metal"

GlobalConfig :: struct {
    vsync: i32,
    window_size: [2]i32,
    depth_format: MTL.PixelFormat,
    raster_sample_count: i32,
}

global_config := GlobalConfig {
    vsync = 2,
    window_size = {1024, 1024},
    depth_format = .Depth32Float, // TODO: Figure out if we can use Depth16Unorm without having artifacts
    raster_sample_count = 1,
}