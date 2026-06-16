const std = @import("std");
const model = @import("model.zig");
const text = @import("text.zig");

pub const Posting = struct {
    object_index: usize,
    weight: i32,
};

pub const TermEntry = struct {
    term: []const u8,
    postings: std.array_list.Managed(Posting),
};

pub const InvertedIndex = struct {
    allocator: std.mem.Allocator,
    terms: std.StringHashMap(*TermEntry),

    pub fn init(allocator: std.mem.Allocator) InvertedIndex {
        return .{ .allocator = allocator, .terms = std.StringHashMap(*TermEntry).init(allocator) };
    }

    pub fn deinit(self: *InvertedIndex) void {
        var it = self.terms.iterator();
        while (it.next()) |e| {
            self.allocator.free(e.key_ptr.*);
            e.value_ptr.*.postings.deinit();
            self.allocator.destroy(e.value_ptr.*);
        }
        self.terms.deinit();
    }

    pub fn build(allocator: std.mem.Allocator, ctx: *const model.Context) !InvertedIndex {
        var idx = InvertedIndex.init(allocator);
        for (ctx.objects.items, 0..) |obj, i| {
            try idx.addText(i, obj.id, 5);
            try idx.addText(i, obj.title, 8);
            try idx.addText(i, obj.path, 3);
            try idx.addText(i, obj.preview, 1);
            try idx.addText(i, model.Context.kindName(obj.kind), 4);
        }
        return idx;
    }

    fn addText(self: *InvertedIndex, object_index: usize, bytes: []const u8, weight: i32) !void {
        var pos: usize = 0;
        while (pos < bytes.len) {
            while (pos < bytes.len and !isTokenByte(bytes[pos])) pos += 1;
            const start = pos;
            while (pos < bytes.len and isTokenByte(bytes[pos])) pos += 1;
            if (pos <= start) continue;
            const raw = bytes[start..pos];
            if (raw.len < 2) continue;
            var tmp = std.array_list.Managed(u8).init(self.allocator);
            defer tmp.deinit();
            const norm = try text.normalizeToken(&tmp, raw);
            try self.addTerm(norm, object_index, weight);
        }
    }

    fn addTerm(self: *InvertedIndex, term: []const u8, object_index: usize, weight: i32) !void {
        if (self.terms.get(term)) |entry| {
            try entry.postings.append(.{ .object_index = object_index, .weight = weight });
            return;
        }
        const owned = try self.allocator.dupe(u8, term);
        const entry = try self.allocator.create(TermEntry);
        entry.* = .{ .term = owned, .postings = std.array_list.Managed(Posting).init(self.allocator) };
        try entry.postings.append(.{ .object_index = object_index, .weight = weight });
        try self.terms.put(owned, entry);
    }

    pub fn lookup(self: *const InvertedIndex, term: []const u8) ?[]const Posting {
        if (self.terms.get(term)) |entry| return entry.postings.items;
        return null;
    }

    pub fn hasExact(self: *const InvertedIndex, term: []const u8) bool {
        return self.terms.contains(term);
    }

    pub fn approxTerms(self: *const InvertedIndex, allocator: std.mem.Allocator, needle: []const u8, limit: usize) !std.array_list.Managed([]const u8) {
        var out = std.array_list.Managed([]const u8).init(allocator);
        var it = self.terms.iterator();
        while (it.next()) |e| {
            if (text.containsFold(e.key_ptr.*, needle)) {
                try out.append(e.key_ptr.*);
                if (out.items.len >= limit) break;
            }
        }
        return out;
    }
};

fn isTokenByte(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_' or c == '-' or c == '.';
}


pub const KindSlotCount = 12;
pub const EdgeSlotCount = 13;
pub const MissingObjectIndex = std.math.maxInt(usize);

pub const SearchIndex = struct {
    allocator: std.mem.Allocator,
    text_index: InvertedIndex,
    src_edges: std.StringHashMap(std.array_list.Managed(usize)),
    dst_edges: std.StringHashMap(std.array_list.Managed(usize)),
    kind_objects: [KindSlotCount]std.array_list.Managed(usize),
    edge_kind_edges: [EdgeSlotCount]std.array_list.Managed(usize),
    out_degree: []usize,
    in_degree: []usize,
    edge_src_object: []usize,
    edge_dst_object: []usize,
    object_count: usize = 0,
    edge_count: usize = 0,

    pub fn build(allocator: std.mem.Allocator, ctx: *const model.Context) !SearchIndex {
        var idx = SearchIndex{
            .allocator = allocator,
            .text_index = try InvertedIndex.build(allocator, ctx),
            .src_edges = std.StringHashMap(std.array_list.Managed(usize)).init(allocator),
            .dst_edges = std.StringHashMap(std.array_list.Managed(usize)).init(allocator),
            .kind_objects = undefined,
            .edge_kind_edges = undefined,
            .out_degree = try allocator.alloc(usize, ctx.objects.items.len),
            .in_degree = try allocator.alloc(usize, ctx.objects.items.len),
            .edge_src_object = try allocator.alloc(usize, ctx.edges.items.len),
            .edge_dst_object = try allocator.alloc(usize, ctx.edges.items.len),
            .object_count = ctx.objects.items.len,
            .edge_count = ctx.edges.items.len,
        };
        @memset(idx.out_degree, 0);
        @memset(idx.in_degree, 0);
        @memset(idx.edge_src_object, MissingObjectIndex);
        @memset(idx.edge_dst_object, MissingObjectIndex);
        var ki: usize = 0;
        while (ki < KindSlotCount) : (ki += 1) idx.kind_objects[ki] = std.array_list.Managed(usize).init(allocator);
        var ei: usize = 0;
        while (ei < EdgeSlotCount) : (ei += 1) idx.edge_kind_edges[ei] = std.array_list.Managed(usize).init(allocator);

        for (ctx.objects.items, 0..) |obj, i| {
            try idx.kind_objects[kindIndex(obj.kind)].append(i);
        }
        for (ctx.edges.items, 0..) |edge, i| {
            try idx.edge_kind_edges[edgeIndex(edge.kind)].append(i);
            try idx.appendEdge(&idx.src_edges, edge.src, i);
            try idx.appendEdge(&idx.dst_edges, edge.dst, i);
            if (ctx.findObject(edge.src)) |si| {
                idx.edge_src_object[i] = si;
                idx.out_degree[si] += 1;
            }
            if (ctx.findObject(edge.dst)) |di| {
                idx.edge_dst_object[i] = di;
                idx.in_degree[di] += 1;
            }
        }
        return idx;
    }

    pub fn deinit(self: *SearchIndex) void {
        self.text_index.deinit();
        deinitEdgeMap(self.allocator, &self.src_edges);
        deinitEdgeMap(self.allocator, &self.dst_edges);
        var ki: usize = 0;
        while (ki < KindSlotCount) : (ki += 1) self.kind_objects[ki].deinit();
        var ei: usize = 0;
        while (ei < EdgeSlotCount) : (ei += 1) self.edge_kind_edges[ei].deinit();
        self.allocator.free(self.out_degree);
        self.allocator.free(self.in_degree);
        self.allocator.free(self.edge_src_object);
        self.allocator.free(self.edge_dst_object);
    }

    fn appendEdge(self: *SearchIndex, map: *std.StringHashMap(std.array_list.Managed(usize)), id: []const u8, edge_index: usize) !void {
        if (map.getPtr(id)) |list| {
            try list.append(edge_index);
            return;
        }
        const owned = try self.allocator.dupe(u8, id);
        var list = std.array_list.Managed(usize).init(self.allocator);
        try list.append(edge_index);
        try map.put(owned, list);
    }

    pub fn outgoing(self: *const SearchIndex, id: []const u8) []const usize {
        if (self.src_edges.get(id)) |list| return list.items;
        return &.{};
    }

    pub fn incoming(self: *const SearchIndex, id: []const u8) []const usize {
        if (self.dst_edges.get(id)) |list| return list.items;
        return &.{};
    }

    pub fn objectsOfKind(self: *const SearchIndex, kind: model.ObjectKind) []const usize {
        return self.kind_objects[kindIndex(kind)].items;
    }

    pub fn edgesOfKind(self: *const SearchIndex, kind: model.EdgeKind) []const usize {
        return self.edge_kind_edges[edgeIndex(kind)].items;
    }

    pub fn edgeSrc(self: *const SearchIndex, edge_index: usize) ?usize {
        if (edge_index >= self.edge_src_object.len) return null;
        const idx = self.edge_src_object[edge_index];
        return if (idx == MissingObjectIndex) null else idx;
    }

    pub fn edgeDst(self: *const SearchIndex, edge_index: usize) ?usize {
        if (edge_index >= self.edge_dst_object.len) return null;
        const idx = self.edge_dst_object[edge_index];
        return if (idx == MissingObjectIndex) null else idx;
    }

    pub fn hasOutgoing(self: *const SearchIndex, object_index: usize) bool {
        return object_index < self.out_degree.len and self.out_degree[object_index] != 0;
    }

    pub fn hasIncoming(self: *const SearchIndex, object_index: usize) bool {
        return object_index < self.in_degree.len and self.in_degree[object_index] != 0;
    }

    pub fn isOrphan(self: *const SearchIndex, object_index: usize) bool {
        return !self.hasOutgoing(object_index) and !self.hasIncoming(object_index);
    }

    pub fn markExactWordCandidates(self: *const SearchIndex, allocator: std.mem.Allocator, word: []const u8, marks: []bool) !usize {
        @memset(marks, false);
        if (word.len == 0) return 0;
        var tmp = std.array_list.Managed(u8).init(allocator);
        defer tmp.deinit();
        const norm = try text.normalizeToken(&tmp, word);
        if (norm.len == 0) return 0;
        if (self.text_index.lookup(norm)) |posts| return markPostings(posts, marks);
        return 0;
    }

    pub fn markWordCandidates(self: *const SearchIndex, allocator: std.mem.Allocator, word: []const u8, marks: []bool) !usize {
        const exact = try self.markExactWordCandidates(allocator, word, marks);
        if (exact != 0) return exact;
        var tmp = std.array_list.Managed(u8).init(allocator);
        defer tmp.deinit();
        const norm = try text.normalizeToken(&tmp, word);
        if (norm.len < 3) return 0;
        var approx = try self.text_index.approxTerms(allocator, norm, 96);
        defer approx.deinit();
        var count: usize = 0;
        for (approx.items) |term| {
            if (self.text_index.lookup(term)) |posts| count += markPostings(posts, marks);
        }
        return countMarked(marks, count);
    }

    pub fn candidateCountForWord(self: *const SearchIndex, allocator: std.mem.Allocator, word: []const u8) !usize {
        const marks = try allocator.alloc(bool, self.object_count);
        defer allocator.free(marks);
        return self.markWordCandidates(allocator, word, marks);
    }
};

fn deinitEdgeMap(allocator: std.mem.Allocator, map: *std.StringHashMap(std.array_list.Managed(usize))) void {
    var it = map.iterator();
    while (it.next()) |e| {
        allocator.free(e.key_ptr.*);
        e.value_ptr.*.deinit();
    }
    map.deinit();
}

fn markPostings(posts: []const Posting, marks: []bool) usize {
    var added: usize = 0;
    for (posts) |p| {
        if (p.object_index >= marks.len) continue;
        if (!marks[p.object_index]) added += 1;
        marks[p.object_index] = true;
    }
    return added;
}

fn countMarked(marks: []const bool, approximate: usize) usize {
    _ = approximate;
    var n: usize = 0;
    for (marks) |m| {
        if (m) n += 1;
    }
    return n;
}

pub fn kindIndex(kind: model.ObjectKind) usize {
    return switch (kind) {
        .file => 0,
        .heading => 1,
        .record => 2,
        .script => 3,
        .report => 4,
        .concept => 5,
        .test_kind => 6,
        .source => 7,
        .info => 8,
        .todo => 9,
        .done => 10,
        .unknown => 11,
    };
}

pub fn edgeIndex(kind: model.EdgeKind) usize {
    return switch (kind) {
        .contains => 0,
        .file_link => 1,
        .id_link => 2,
        .supports => 3,
        .supersedes => 4,
        .verifies => 5,
        .blocks => 6,
        .refines => 7,
        .classifies_as => 8,
        .forgets_to => 9,
        .generated_by => 10,
        .mentions => 11,
        .unknown => 12,
    };
}

test "index empty" {
    var idx = InvertedIndex.init(std.testing.allocator);
    defer idx.deinit();
    try std.testing.expect(idx.lookup("x") == null);
}


test "search index builds adjacency, kinds, and term candidates" {
    var ctx = try model.Context.init(std.testing.allocator, ".");
    defer ctx.deinit();
    _ = try ctx.addObject(.{ .id = "src.reader", .kind = .source, .title = "reader source", .path = "src/reader.c", .preview = "rareneedle parser implementation" });
    _ = try ctx.addObject(.{ .id = "test.reader", .kind = .test_kind, .title = "reader test", .path = "tests/reader.mon", .preview = "verifies rareneedle" });
    _ = try ctx.addObject(.{ .id = "todo.codegen", .kind = .todo, .title = "TODO codegen", .path = "context/todo.org", .preview = "unrelated" });
    _ = try ctx.addEdge(.{ .id = "e.verify", .kind = .verifies, .src = "test.reader", .dst = "src.reader" });

    var idx = try SearchIndex.build(std.testing.allocator, &ctx);
    defer idx.deinit();
    try std.testing.expect(idx.objectsOfKind(.source).len == 1);
    try std.testing.expect(idx.edgesOfKind(.verifies).len == 1);
    try std.testing.expect(idx.outgoing("test.reader").len == 1);
    try std.testing.expect(idx.incoming("src.reader").len == 1);
    try std.testing.expect(idx.edgeSrc(0).? == 1);
    try std.testing.expect(idx.edgeDst(0).? == 0);
    try std.testing.expect(!idx.isOrphan(0));
    const rare_count = try idx.candidateCountForWord(std.testing.allocator, "rareneedle");
    try std.testing.expect(rare_count == 2);
}

test "indexed candidate path stays selective on synthetic corpus" {
    var ctx = try model.Context.init(std.testing.allocator, ".");
    defer ctx.deinit();
    var i: usize = 0;
    while (i < 320) : (i += 1) {
        var id_buf: [64]u8 = undefined;
        var title_buf: [96]u8 = undefined;
        const id = try std.fmt.bufPrint(&id_buf, "obj.{d}", .{i});
        const title = try std.fmt.bufPrint(&title_buf, "ordinary object {d}", .{i});
        const preview = if (i % 64 == 0) "needlefast indexed benchmark marker" else "ordinary context text";
        _ = try ctx.addObject(.{ .id = id, .kind = .record, .title = title, .path = "context/synth.org", .preview = preview });
    }
    var idx = try SearchIndex.build(std.testing.allocator, &ctx);
    defer idx.deinit();
    const candidates = try idx.candidateCountForWord(std.testing.allocator, "needlefast");
    std.debug.print("catface perf: indexed candidates for needlefast = {d}/{d}\n", .{ candidates, ctx.objects.items.len });
    try std.testing.expect(candidates == 5);
    try std.testing.expect(candidates < ctx.objects.items.len / 8);
}

test "exact candidate marking reuses caller scratch buffer" {
    var ctx = try model.Context.init(std.testing.allocator, ".");
    defer ctx.deinit();
    _ = try ctx.addObject(.{ .id = "a", .kind = .record, .title = "alpha", .preview = "needle" });
    _ = try ctx.addObject(.{ .id = "b", .kind = .record, .title = "beta", .preview = "hay" });
    var idx = try SearchIndex.build(std.testing.allocator, &ctx);
    defer idx.deinit();
    const marks = try std.testing.allocator.alloc(bool, ctx.objects.items.len);
    defer std.testing.allocator.free(marks);
    const n = try idx.markExactWordCandidates(std.testing.allocator, "needle", marks);
    try std.testing.expect(n == 1);
    try std.testing.expect(marks[0]);
    try std.testing.expect(!marks[1]);
}
