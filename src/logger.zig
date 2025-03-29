const std = @import("std");
const builtin = @import("builtin");

pub fn scoped(comptime scope: @Type(.enum_literal)) type {
    const logger = std.log.scoped(scope);
    return if (builtin.is_test) struct {
        pub const err = logger.warn;
        pub const warn = logger.warn;
        pub const info = logger.info;
        pub const debug = logger.debug;
    } else logger;
}
