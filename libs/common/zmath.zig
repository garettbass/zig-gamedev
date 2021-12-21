const std = @import("std");
const math = std.math;
const assert = std.debug.assert;

pub const Vec = @Vector(4, f32);

pub inline fn vecZero() Vec {
    // _mm_setzero_ps()
    return @splat(4, @as(f32, 0));
}

pub inline fn vecSet(x: f32, y: f32, z: f32, w: f32) Vec {
    return [4]f32{ x, y, z, w };
}

pub inline fn vecSetInt(x: u32, y: u32, z: u32, w: u32) Vec {
    const vu = [4]u32{ x, y, z, w };
    return @bitCast(Vec, vu);
}

pub inline fn vecReplicate(value: f32) Vec {
    return @splat(4, value);
}

pub inline fn vecReplicateInt(value: u32) Vec {
    return @splat(4, @bitCast(f32, value));
}

pub inline fn vecTrueInt() Vec {
    const static = struct {
        const v = vecReplicateInt(0xffff_ffff);
    };
    return static.v;
}

pub inline fn vecFalseInt() Vec {
    return vecZero();
}

pub inline fn vecLess(v0: Vec, v1: Vec) Vec {
    return @select(f32, v0 < v1, vecTrueInt(), vecFalseInt());
}

pub inline fn vecLessOrEqual(v0: Vec, v1: Vec) Vec {
    return @select(f32, v0 <= v1, vecTrueInt(), vecFalseInt());
}

pub inline fn vecNearEqual(v0: Vec, v1: Vec, epsilon: Vec) Vec {
    const delta = v0 - v1;
    var temp = vecZero();
    temp = temp - delta;
    temp = @maximum(temp, delta);
    return vecLessOrEqual(temp, epsilon);
}

pub inline fn vecAnd(v0: Vec, v1: Vec) Vec {
    const v0u = @bitCast(@Vector(4, u32), v0);
    const v1u = @bitCast(@Vector(4, u32), v1);
    const vu = v0u & v1u;
    return @bitCast(Vec, vu);
}

pub inline fn vecAdd(v0: Vec, v1: Vec) Vec {
    return v0 + v1;
}

fn vecApproxEqAbs(v0: Vec, v1: Vec, eps: f32) bool {
    return math.approxEqAbs(f32, v0[0], v1[0], eps) and
        math.approxEqAbs(f32, v0[1], v1[1], eps) and
        math.approxEqAbs(f32, v0[2], v1[2], eps) and
        math.approxEqAbs(f32, v0[3], v1[3], eps);
}

pub inline fn vecLoadFloat2(ptr: []const f32) Vec {
    return vecSet(ptr[0], ptr[1], 0.0, 0.0);
}

pub inline fn vecLoadFloat3(ptr: []const f32) Vec {
    return vecSet(ptr[0], ptr[1], ptr[2], 0.0);
}

pub inline fn vecLoadFloat4(ptr: []const f32) Vec {
    return vecSet(ptr[0], ptr[1], ptr[2], ptr[4]);
}

test "basic" {
    {
        const v0 = vecSet(1.0, 2.0, 3.0, 4.0);
        const v1 = vecSet(5.0, 6.0, 7.0, 8.0);
        assert(v0[0] == 1.0 and v0[1] == 2.0 and v0[2] == 3.0 and v0[3] == 4.0);
        assert(v1[0] == 5.0 and v1[1] == 6.0 and v1[2] == 7.0 and v1[3] == 8.0);
        const v = vecAdd(v0, v1);
        assert(vecApproxEqAbs(v, [4]f32{ 6.0, 8.0, 10.0, 12.0 }, 0.00001));
    }
    {
        const v = vecReplicate(123.0);
        assert(vecApproxEqAbs(v, [4]f32{ 123.0, 123.0, 123.0, 123.0 }, 0.0));
    }
    {
        const v = vecZero();
        assert(vecApproxEqAbs(v, [4]f32{ 0.0, 0.0, 0.0, 0.0 }, 0.0));
    }
    {
        const v = vecReplicateInt(0x4000_0000);
        assert(vecApproxEqAbs(v, [4]f32{ 2.0, 2.0, 2.0, 2.0 }, 0.0));
    }
    {
        const v = vecSetInt(0x3f80_0000, 0x4000_0000, 0x4040_0000, 0x4080_0000);
        assert(vecApproxEqAbs(v, [4]f32{ 1.0, 2.0, 3.0, 4.0 }, 0.0));
    }
    {
        const v0 = vecSet(1.0, 3.0, 2.0, 7.0);
        const v1 = vecSet(2.0, 1.0, 4.0, 7.0);
        const vmin = @minimum(v0, v1);
        const vmax = @maximum(v0, v1);
        const less = v0 < v1;
        assert(vecApproxEqAbs(vmin, [4]f32{ 1.0, 1.0, 2.0, 7.0 }, 0.0));
        assert(vecApproxEqAbs(vmax, [4]f32{ 2.0, 3.0, 4.0, 7.0 }, 0.0));
        assert(less[0] == true and less[1] == false and less[2] == true and less[3] == false);
    }
    {
        const v0 = vecSet(1.0, 3.0, 2.0, 7.0);
        const v1 = vecSet(1.0, 1.0, -2.0, 7.001);
        const v = vecNearEqual(v0, v1, vecReplicate(0.01));
        assert(@bitCast(u32, v[0]) == 0xffff_ffff);
        assert(@bitCast(u32, v[1]) == 0x0000_0000);
        assert(@bitCast(u32, v[2]) == 0x0000_0000);
        assert(@bitCast(u32, v[3]) == 0xffff_ffff);
        const vv = vecAnd(v0, v);
        assert(vv[0] == 1.0);
        assert(vv[1] == 0.0);
        assert(vv[2] == 0.0);
        assert(vv[3] == 7.0);
        assert(vecApproxEqAbs(vv, [4]f32{ 1.0, 0.0, 0.0, 7.0 }, 0.0));
    }
    {
        const a = [7]f32{ 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0 };
        var ptr = &a;
        var i: u32 = 0;
        const v0 = vecLoadFloat2(a[i..]);
        assert(vecApproxEqAbs(v0, [4]f32{ 1.0, 2.0, 0.0, 0.0 }, 0.0));
        i += 2;
        const v1 = vecLoadFloat2(a[i .. i + 2]);
        assert(vecApproxEqAbs(v1, [4]f32{ 3.0, 4.0, 0.0, 0.0 }, 0.0));
        const v2 = vecLoadFloat2(a[5..7]);
        assert(vecApproxEqAbs(v2, [4]f32{ 6.0, 7.0, 0.0, 0.0 }, 0.0));
        const v3 = vecLoadFloat2(ptr[1..]);
        assert(vecApproxEqAbs(v3, [4]f32{ 2.0, 3.0, 0.0, 0.0 }, 0.0));
        i += 1;
        const v4 = vecLoadFloat2(ptr[i .. i + 2]);
        assert(vecApproxEqAbs(v4, [4]f32{ 4.0, 5.0, 0.0, 0.0 }, 0.0));
    }
}