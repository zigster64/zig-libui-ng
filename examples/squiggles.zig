const std = @import("std");
const ui = @import("ui");

const DrawMode = enum(u8) {
    None = 0,
    Line = 1,
    Fill = 2,
};

const Point = struct {
    x: f64,
    y: f64,
};
const PointList = std.ArrayList(Point);

const Line = struct {
    mode: DrawMode,
    brush: ui.Draw.Brush.InitOptions,
    points: PointList,
};
const Lines = std.ArrayList(Line);

const CustomWidget = struct {
    gpa: std.mem.Allocator,
    handler: ui.Area.Handler,
    points: ?PointList = null,
    lines: Lines,
    rng: std.rand.DefaultPrng,
    draw_mode: DrawMode = .None,

    pub fn New(gpa: std.mem.Allocator) !*@This() {
        const this = try gpa.create(@This());
        errdefer gpa.destroy(this);
        this.* = .{
            .gpa = gpa,
            .rng = std.rand.DefaultPrng.init(blk: {
                var seed: u64 = undefined;
                try std.os.getrandom(std.mem.asBytes(&seed));
                break :blk seed;
            }),
            .handler = ui.Area.Handler{
                .Draw = @This().Draw,
                .MouseEvent = @This().MouseEvent,
                .MouseCrossed = @This().MouseCrossed,
                .DragBroken = @This().DragBroken,
                .KeyEvent = @This().KeyEvent,
            },
            .lines = Lines.init(gpa),
        };
        return this;
    }

    pub fn Destroy(this: *@This()) void {
        if (this.points) |*points| {
            points.deinit();
        }
        for (this.lines.items) |line| {
            line.points.deinit();
        }
        this.lines.deinit();
        this.gpa.destroy(this);
    }

    pub fn NewArea(this: *@This()) !*ui.Area {
        return this.handler.New(.Area);
    }

    fn drawPoints(points: PointList, draw_params: *ui.Draw.Params, mode: DrawMode, brush_options: ui.Draw.Brush.InitOptions) void {
        var stroke_params = ui.Draw.StrokeParams.init(.{});
        var line_path = ui.Draw.Path.New(.Winding) orelse return;
        defer line_path.Free();
        var line_brush = ui.Draw.Brush.init(brush_options);
        line_path.NewFigure(points.items[0].x, points.items[0].y);
        for (points.items) |point| {
            line_path.LineTo(point.x, point.y);
        }

        switch (mode) {
            .None => return,
            .Line => {
                line_path.End();
                draw_params.Context.?.Stroke(line_path, &line_brush, &stroke_params);
            },
            .Fill => {
                // add one more point to connect it back to the origin
                const first = points.items[0];
                line_path.LineTo(first.x, first.y);
                line_path.End();
                draw_params.Context.?.Fill(line_path, &line_brush);
            },
        }
    }

    fn randPastel(this: *@This()) f64 {
        return this.rng.random().float(f64) * 0.2 + 0.6;
    }

    fn Draw(handler: *ui.Area.Handler, area: *ui.Area, draw_params: *ui.Draw.Params) callconv(.C) void {
        _ = area;
        const this: *@This() = @fieldParentPtr(@This(), "handler", handler);

        // Draw the contents of the current points array in green
        if (this.points) |points| {
            drawPoints(points, draw_params, this.draw_mode, .{
                .Type = .Solid,
                .R = 0,
                .G = 1,
                .B = 0,
            });
        }
        for (this.lines.items) |line| {
            drawPoints(line.points, draw_params, line.mode, line.brush);
        }
    }

    fn MouseEvent(handler: *ui.Area.Handler, area: *ui.Area, mouse_event: *ui.Area.MouseEvent) callconv(.C) void {
        const this: *@This() = @fieldParentPtr(@This(), "handler", handler);
        if (mouse_event.Down > 0) {
            this.draw_mode = switch (mouse_event.Down) {
                1 => .Line,
                3 => .Fill,
                else => {
                    std.debug.print("Ignoring mouse button {}\n", .{mouse_event.Down});
                    return; // ignore other button presses
                },
            };
            // if (this.points) |points| {
                points.deinit();
            }
            this.points = PointList.init(this.gpa);
        }
        if (mouse_event.Up > 0) {
            if (this.points) |points| {
                // save the array of points to the array of lines
        var gradient = ui.Draw.Brush.GradientStop{
                            .{ .Pos = 0.0, .R = this.randPastel(), .G = this.randPastel(), .B = this.randPastel(), .A = 0.2 },
                            .{ .Pos = 1.0, .R = this.randPastel(), .G = this.randPastel(), .B = this.randPastel(), .A = 0.2 },
        };
                this.lines.append(.{
                    .points = points,
                    .brush = .{
                        .Type = .LinearGradient,
                        .R = this.randPastel(),
                        .G = this.randPastel(),
                        .B = this.randPastel(),
                        .A = this.randPastel(),
                        .Stops = gradient,
                    },
                    .mode = this.draw_mode,
                }) catch {};
                this.points = null;
            }
            this.draw_mode = .None;
            area.QueueRedrawAll();
        }
        if (this.draw_mode != .None) {
            if (this.points) |_| {
                this.points.?.append(.{ .x = mouse_event.X, .y = mouse_event.Y }) catch return;
            } else unreachable;
            area.QueueRedrawAll();
        }
    }

    fn MouseCrossed(handler: *ui.Area.Handler, area: *ui.Area, cross_value: c_int) callconv(.C) void {
        _ = cross_value;
        _ = handler;
        _ = area;
    }

    fn DragBroken(handler: *ui.Area.Handler, area: *ui.Area) callconv(.C) void {
        _ = handler;
        _ = area;
    }

    fn KeyEvent(handler: *ui.Area.Handler, area: *ui.Area, key_event: *ui.Area.KeyEvent) callconv(.C) c_int {
        _ = handler;
        _ = area;
        _ = key_event;
        return 0;
    }
};

pub fn on_closing(_: *ui.Window, _: ?*void) ui.Window.ClosingAction {
    ui.Quit();
    return .should_close;
}

pub fn main() !void {
    var gpa_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_allocator.deinit();
    const gpa = gpa_allocator.allocator();

    var init_data = ui.InitData{
        .options = .{ .Size = 0 },
    };
    ui.Init(&init_data) catch {
        std.debug.print("Error initializing LibUI: {s}\n", .{init_data.get_error()});
        init_data.free_error();
        return;
    };
    defer ui.Uninit();

    const main_window = try ui.Window.New("Squiggle Draw Pro", 320, 240, .hide_menubar);

    main_window.as_control().Show();
    main_window.OnClosing(void, on_closing, null);

    const box = try ui.Box.New(.Vertical);
    main_window.SetChild(box.as_control());

    const custom_widget = try CustomWidget.New(gpa);
    defer custom_widget.Destroy();

    const custom_widget_area = try custom_widget.NewArea();
    box.Append(custom_widget_area.as_control(), .stretch);

    ui.Main();
}
