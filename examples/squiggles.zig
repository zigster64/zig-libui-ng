const std = @import("std");
const ui = @import("ui");

const Point = struct {
    x: f64,
    y: f64,
};
const PointList = std.ArrayList(Point);
const Lines = std.ArrayList(PointList);

const DrawMode = enum(u8) {
    None = 0,
    Line = 1,
    Fill = 2,
};

const CustomWidget = struct {
    gpa: std.mem.Allocator,
    handler: ui.Area.Handler,
    points: ?PointList = null,
    lines: Lines,
    drawing: DrawMode = .None,

    pub fn New(gpa: std.mem.Allocator) !*@This() {
        const this = try gpa.create(@This());
        errdefer gpa.destroy(this);
        this.* = .{
            .gpa = gpa,
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
        for (this.lines.items) |point| {
            point.deinit();
        }
        this.lines.deinit();
        this.gpa.destroy(this);
    }

    pub fn NewArea(this: *@This()) !*ui.Area {
        return this.handler.New(.Area);
    }

    fn drawPoints(points: PointList, draw_params: *ui.Draw.Params, brush_options: ui.Draw.Brush.InitOptions) void {
        var stroke_params = ui.Draw.StrokeParams.init(.{});
        var line_path = ui.Draw.Path.New(.Winding) orelse return;
        defer line_path.Free();
        var line_brush = ui.Draw.Brush.init(brush_options);
        line_path.NewFigure(points.items[0].x, points.items[0].y);
        for (points.items) |point| {
            line_path.LineTo(point.x, point.y);
        }
        line_path.End();
        draw_params.Context.?.Stroke(line_path, &line_brush, &stroke_params);
    }

    fn Draw(handler: *ui.Area.Handler, area: *ui.Area, draw_params: *ui.Draw.Params) callconv(.C) void {
        _ = area;
        const this: *@This() = @fieldParentPtr(@This(), "handler", handler);

        // Draw some text
        var font_descriptor: ui.FontDescriptor = undefined;
        font_descriptor.LoadControlFont();
        defer font_descriptor.Free();

        font_descriptor.Size = 24;

        const text = ui.AttributedString.uiNewAttributedString("This is my custom widget!") orelse return;
        defer text.Free();

        var text_layout_params = ui.Draw.TextLayout.Params{
            .String = text,
            .DefaultFont = &font_descriptor,
            .Width = draw_params.AreaWidth,
            .Align = .Center,
        };

        const text_layout = ui.Draw.TextLayout.New(&text_layout_params) catch return;
        defer text_layout.Free();

        draw_params.Context.?.Text(text_layout, 0, 0);

        // Draw some semi-circles below the text
        const text_extents = text_layout.TextLayoutExtents();
        var brush = ui.Draw.Brush.init(.{});

        // Draw the outline of a semi-circle
        var stroke_path = ui.Draw.Path.New(.Winding) orelse return;
        defer stroke_path.Free();
        stroke_path.NewFigureWithArc(draw_params.AreaWidth / 2 - 24, text_extents.y + 12, 12, 0, std.math.pi, 0);
        stroke_path.End();
        var stroke_params = ui.Draw.StrokeParams.init(.{});
        draw_params.Context.?.Stroke(stroke_path, &brush, &stroke_params);

        // Draw a filled semi-circle
        var fill_path = ui.Draw.Path.New(.Winding) orelse return;
        defer fill_path.Free();
        fill_path.NewFigureWithArc(draw_params.AreaWidth / 2 + 24, text_extents.y + 12, 12, 0, std.math.pi, 0);
        fill_path.End();
        draw_params.Context.?.Fill(fill_path, &brush);

        // Draw the contents of the current points array in green
        if (this.points) |points| {
            drawPoints(points, draw_params, .{
                .Type = .Solid,
                .R = 0,
                .G = 1,
                .B = 0,
            });
        }
        for (this.lines.items) |line| {
            drawPoints(line, draw_params, .{
                .Type = .Solid,
                .R = 0,
                .G = 0.8,
                .B = 0.8,
            });
        }
    }

    fn MouseEvent(handler: *ui.Area.Handler, area: *ui.Area, mouse_event: *ui.Area.MouseEvent) callconv(.C) void {
        const this: *@This() = @fieldParentPtr(@This(), "handler", handler);
        if (mouse_event.Down > 0) {
            this.drawing = switch (mouse_event.Down) {
                1 => .Line,
                2 => .Fill,
                else => return, // ignore other button presses
            };
            if (this.points) |points| {
                points.deinit();
            }
            this.points = PointList.init(this.gpa);
        }
        if (mouse_event.Up == 1) {
            if (this.points) |points| {
                // save the array of points to the array of lines
                this.lines.append(points) catch {};
                this.points = null;
            }
            this.drawing = .None;
            area.QueueRedrawAll();
        }
        if (this.drawing != .None) {
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

    const main_window = try ui.Window.New("Draw some lines", 320, 240, .hide_menubar);

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
