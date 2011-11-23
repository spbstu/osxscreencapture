/*
 * GStreamer
 * Copyright (C) 2005 Thomas Vander Stichele <thomas@apestaart.org>
 * Copyright (C) 2005 Ronald S. Bultje <rbultje@ronald.bitfreak.net>
 * Copyright (C) 2011  <<user@hostname.org>>
 * 
 * Permission is hereby granted, free of charge, to any person obtaining a
 * copy of this software and associated documentation files (the "Software"),
 * to deal in the Software without restriction, including without limitation
 * the rights to use, copy, modify, merge, publish, distribute, sublicense,
 * and/or sell copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 * DEALINGS IN THE SOFTWARE.
 *
 * Alternatively, the contents of this file may be used under the
 * GNU Lesser General Public License Version 2.1 (the "LGPL"), in
 * which case the following provisions apply instead of the ones
 * mentioned above:
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Library General Public License for more details.
 *
 * You should have received a copy of the GNU Library General Public
 * License along with this library; if not, write to the
 * Free Software Foundation, Inc., 59 Temple Place - Suite 330,
 * Boston, MA 02111-1307, USA.
 */

/**
 * SECTION:element-screencapturesrc
 *
 * FIXME:Describe screencapturesrc here.
 *
 * <refsect2>
 * <title>Example launch line</title>
 * |[
 * gst-launch -v -m fakesrc ! screencapturesrc ! fakesink silent=TRUE
 * ]|
 * </refsect2>
 */

#ifdef HAVE_CONFIG_H
#  include <config.h>
#endif

#include "gstscreencapturesrc.h"

#include <gst/gst.h>
#include <gst/video/video.h>

#define DEVICE_FPS_N          30
#define DEVICE_FPS_D          1

#define FRAME_QUEUE_SIZE      2

#define OBJC_CALLOUT_BEGIN() \
NSAutoreleasePool *pool; \
\
pool = [[NSAutoreleasePool alloc] init]
#define OBJC_CALLOUT_END() \
[pool release]


GST_DEBUG_CATEGORY_STATIC (gst_screen_capture_src_debug);
#define GST_CAT_DEFAULT gst_screen_capture_src_debug

/* the capabilities of the inputs and outputs.
 *
 * describe the real formats here.
 */

static GstStaticPadTemplate src_factory = GST_STATIC_PAD_TEMPLATE ("src",
    GST_PAD_SRC,
    GST_PAD_ALWAYS,
    GST_STATIC_CAPS (GST_VIDEO_CAPS_RGBx)
    );

GST_BOILERPLATE (GstScreenCaptureSrc, gst_screen_capture_src, GstPushSrc,
                 GST_TYPE_PUSH_SRC);


@interface GstScreenCaptureSrcImpl : NSObject {
    GstElement *element;
    GstBaseSrc *baseSrc;
    GstPushSrc *pushSrc;
    
    BOOL cursor;
    
    gint width, height;
    gint fps_n, fps_d;
    gint64 frames;
    NSRect screenRect;
    CGContextRef context;
    
}

@property BOOL cursor;

- (id)init;
- (id)initWithSrc:(GstPushSrc *)src;
- (BOOL)setCaps:(GstCaps *)caps;
- (GstCaps *)getCaps;
- (BOOL)start1;
- (BOOL)stop;
- (void)fixate:(GstCaps *)caps;
- (void) getTimes:(GstBuffer *) buffer
           vStart:(GstClockTime *) start
             vEnd:(GstClockTime *) end;

- (GstFlowReturn) create:(GstBuffer **)buf;

@end

@implementation GstScreenCaptureSrcImpl

- (id)init
{
    return [self initWithSrc:NULL];
}

- (id)initWithSrc:(GstPushSrc *)src
{
    if ((self = [super init])) {
        
        [NSApplication sharedApplication];
        
        element = GST_ELEMENT_CAST (src);
        baseSrc = GST_BASE_SRC_CAST (src);
        pushSrc = src;
        
        cursor = FALSE;

        gst_base_src_set_live (baseSrc, TRUE);
        gst_base_src_set_format (baseSrc, GST_FORMAT_TIME);
    }
    
    return self;
}

@synthesize cursor;

- (BOOL)setCaps:(GstCaps *)caps
{
    GstStructure *structure;
    gint red_mask, green_mask, blue_mask;
    gint bpp;
    
    GST_INFO ("setting up session");
    
    structure = gst_caps_get_structure (caps, 0);
    
    gst_structure_get_int (structure, "red_mask", &red_mask);
    gst_structure_get_int (structure, "green_mask", &green_mask);
    gst_structure_get_int (structure, "blue_mask", &blue_mask);
    if (blue_mask != GST_VIDEO_BYTE1_MASK_32_INT ||
        green_mask != GST_VIDEO_BYTE2_MASK_32_INT ||
        red_mask != GST_VIDEO_BYTE3_MASK_32_INT) {
        GST_ERROR ("Wrong red_,green_,blue_ mask provided. "
                   "We only support RGB");
        
        return NO;
    }
    
    gst_structure_get_int (structure, "bpp", &bpp);
    if (bpp != 32) {
        GST_ERROR ("Wrong bpp provided %d. We only support 32 bpp", bpp);
        return NO;
    }
    
    gst_structure_get_int (structure, "width", &width);
    gst_structure_get_int (structure, "height", &height);
    if (!gst_structure_get_fraction (structure, "framerate", &fps_n, &fps_d)) {
        fps_n = DEVICE_FPS_N;
        fps_d = DEVICE_FPS_D;
    }
    
    GST_INFO ("got caps %dx%d %d/%d", width, height, fps_n, fps_d);
    
    CGImageRef cgImageRef = CGWindowListCreateImage(screenRect, kCGWindowListOptionOnScreenOnly, kCGNullWindowID, kCGWindowImageDefault);
    
    CGColorSpaceRef colorSpaceRef = CGImageGetColorSpace(cgImageRef);
    
    context = CGBitmapContextCreate(NULL, width, height,
                                                 CGImageGetBitsPerComponent(cgImageRef),
                                                 CGImageGetBytesPerRow(cgImageRef),
                                                 colorSpaceRef,
                                                 CGImageGetBitmapInfo(cgImageRef));
    CGColorSpaceRelease( colorSpaceRef );
    
    CGImageRelease(cgImageRef);
    
    return YES;
}

- (GstCaps *)getCaps
{
    screenRect = [[NSScreen mainScreen] frame];
    
    return gst_caps_new_simple ("video/x-raw-rgb",
                                "bpp", G_TYPE_INT, 32,
                                "depth", G_TYPE_INT, 24,
                                "endianness", G_TYPE_INT, G_BIG_ENDIAN,
                                "red_mask", G_TYPE_INT, GST_VIDEO_BYTE3_MASK_32_INT,
                                "green_mask", G_TYPE_INT, GST_VIDEO_BYTE2_MASK_32_INT,
                                "blue_mask", G_TYPE_INT, GST_VIDEO_BYTE1_MASK_32_INT,
                                "width", G_TYPE_INT, (int) screenRect.size.width,
                                "height", G_TYPE_INT, (int) screenRect.size.height,
                                "framerate", GST_TYPE_FRACTION_RANGE, 1, G_MAXINT, G_MAXINT, 1, NULL);}

- (BOOL)start1
{
    frames = 0;
    width = height = 0;
    fps_n = 0;
    fps_d = 1;
    
    return YES;
}

- (BOOL)stop
{
    frames = 0;
    
    return YES;
}

- (void)fixate:(GstCaps *)caps
{
    GstStructure *structure;
    
    gst_caps_truncate (caps);
    structure = gst_caps_get_structure (caps, 0);
    gst_structure_fixate_field_nearest_int (structure, "width", 640);
    gst_structure_fixate_field_nearest_int (structure, "height", 480);
    if (gst_structure_has_field (structure, "framerate")) {
        gst_structure_fixate_field_nearest_fraction (structure, "framerate",
                                                     DEVICE_FPS_N, DEVICE_FPS_D);
    }
}

-(void) getTimes:(GstBuffer *) buffer
          vStart:(GstClockTime *) start
            vEnd:(GstClockTime *) end
{
    GstClockTime timestamp;

    timestamp = GST_BUFFER_TIMESTAMP (buffer);

    if (GST_CLOCK_TIME_IS_VALID (timestamp)) {
        GstClockTime duration = GST_BUFFER_DURATION (buffer);

        if (GST_CLOCK_TIME_IS_VALID (duration))
            *end = timestamp + duration;
        *start = timestamp;
    }
}

-(GstFlowReturn) create:(GstBuffer **) buf
{
    GstScreenCaptureSrc *src = GST_SCREENCAPTURESRC (pushSrc);
    GstBuffer *new_buf;
    GstFlowReturn res;
    gint new_buf_size;
    GstClock *clock;
    GstClockTime time;
    GstClockTime base_time;
    CGImageRef cgImageRef = nil;
    CGImageRef cgCurImageRef = nil;
    NSImage *cursorImage;
    
    if (G_UNLIKELY (!width ||
                    !height)) {
        GST_ELEMENT_ERROR (src, CORE, NEGOTIATION, (NULL),
                           ("format wasn't negotiated before create function"));
        return GST_FLOW_NOT_NEGOTIATED;
    } else if (G_UNLIKELY (fps_n == 0 && frames == 1)) {
        GST_DEBUG_OBJECT (src, "eos: 0 framerate, frame %d", (gint) frames);
        return GST_FLOW_UNEXPECTED;
    }
    
    new_buf_size = GST_ROUND_UP_4 (width * 4) * height;
    
    GST_INFO_OBJECT(src,
                    "creating buffer of %d bytes with %dx%d image for frame %d",
                    new_buf_size, width,
                    height, (gint) frames);
    
    GST_INFO_OBJECT(src, "dst buffer of %d kbytes", GST_BUFFER_SIZE(buf));
    
    res =
    gst_pad_alloc_buffer_and_set_caps (GST_BASE_SRC_PAD (src),
                                       GST_BUFFER_OFFSET_NONE, new_buf_size,
                                       GST_PAD_CAPS (GST_BASE_SRC_PAD (pushSrc)), &new_buf);
    if (res != GST_FLOW_OK) {
        GST_DEBUG_OBJECT (src, "could not allocate buffer, reason %s",
                          gst_flow_get_name (res));
        return res;
    }
    
    clock = gst_element_get_clock (GST_ELEMENT (src));
    if (clock) {
        /* Calculate sync time. */
        GstClockTime frame_time =
        gst_util_uint64_scale_int (frames * GST_SECOND,
                                   fps_d, fps_n);
        
        time = gst_clock_get_time (clock);
        base_time = gst_element_get_base_time (GST_ELEMENT (src));
        GST_BUFFER_TIMESTAMP (new_buf) = MAX (time - base_time, frame_time);
    } else {
        GST_BUFFER_TIMESTAMP (new_buf) = GST_CLOCK_TIME_NONE;
    }
    
    /* Do screen capture and put it into buffer... */
    
    cgImageRef = CGWindowListCreateImage(screenRect, kCGWindowListOptionOnScreenOnly, kCGNullWindowID, kCGWindowImageDefault);
    
    if (cursor) {
        
        GST_INFO_OBJECT(src, "Use cursor: yes");        
        cursorImage = [[NSCursor currentSystemCursor] image];
        
        if (cursorImage) {
            
            CGEventRef ourEvent = CGEventCreate(NULL);
            NSPoint point = CGEventGetLocation(ourEvent);
            point.y = (CGFloat)height - point.y;
            GST_INFO_OBJECT(src, "Change cursor position %fx%f", point.x, point.y);
            if (context) {
                GST_INFO_OBJECT(src, "Drawing mouse cursor on screen capture");
                CGContextDrawImage(context, screenRect, cgImageRef);
                [NSGraphicsContext saveGraphicsState];
				[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithGraphicsPort:context flipped:NO]];
				[cursorImage drawAtPoint:point fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0];
				[NSGraphicsContext restoreGraphicsState];
                cgCurImageRef = CGBitmapContextCreateImage(context);
                
            } else {
                GST_INFO_OBJECT(src, "Cannot create contex for drawing mouse cursor");
            };
        } else {
            GST_INFO_OBJECT(src, "Cannot get image mouse cursor");
        };
    } else {
        GST_INFO_OBJECT(src, "Use cursor: no");
    };
    
    CGDataProviderRef dataProvider;
    if (cursor && cgCurImageRef) {
        dataProvider = CGImageGetDataProvider(cgCurImageRef);
    } else {
        dataProvider = CGImageGetDataProvider(cgImageRef);
    };
    
    CFDataRef data = CGDataProviderCopyData(dataProvider);
    
    GST_INFO_OBJECT(src, "Data size of %d", CFDataGetLength(data));
    
    CFDataGetBytes (data, CFRangeMake(0, new_buf_size), GST_BUFFER_DATA (new_buf));

    CFRelease(data);
    
    CGImageRelease(cgImageRef);
    
    if (cursor && cgCurImageRef)
        CGImageRelease(cgCurImageRef);   
    
    if (fps_n) {
        GST_BUFFER_DURATION (new_buf) =
        gst_util_uint64_scale_int (GST_SECOND,
                                   fps_d, fps_n);
        if (clock) {
            GST_BUFFER_DURATION (new_buf) =
            MAX (GST_BUFFER_DURATION (new_buf),
                 gst_clock_get_time (clock) - time);
        }
    } else {
        /* NONE means forever */
        GST_BUFFER_DURATION (new_buf) = GST_CLOCK_TIME_NONE;
    }
    
    GST_BUFFER_OFFSET (new_buf) = frames;
    frames++;
    GST_BUFFER_OFFSET_END (new_buf) = frames;
    
    gst_object_unref (clock);
    
    *buf = new_buf;
    
    return GST_FLOW_OK;
}

@end

/* SRC args */
enum
{
  PROP_0,
  PROP_SHOW_CURSOR
};

static void gst_screen_capture_src_finalize (GObject * obj);
static void gst_screen_capture_src_set_property (GObject * object, guint prop_id, const GValue * value, GParamSpec * pspec);
static void gst_screen_capture_src_get_property (GObject * object, guint prop_id, GValue * value, GParamSpec * pspec);
static void gst_screen_capture_src_fixate (GstBaseSrc * basesrc, GstCaps * caps);
static gboolean gst_screen_capture_src_set_caps (GstBaseSrc * basesrc, GstCaps * caps);
static GstCaps *gst_screen_capture_src_get_caps (GstBaseSrc * basesrc);
static gboolean gst_screen_capture_src_start (GstBaseSrc * basesrc);
static gboolean gst_screen_capture_src_stop (GstBaseSrc * basesrc);
static void gst_screen_capture_src_get_times (GstBaseSrc * basesrc, GstBuffer * buffer, GstClockTime * start, GstClockTime * end);
static GstFlowReturn gst_screen_capture_src_create (GstPushSrc * src, GstBuffer ** buf);

/* GObject vmethod implementations */

static void
gst_screen_capture_src_base_init (gpointer gclass)
{
  GstElementClass *element_class = GST_ELEMENT_CLASS (gclass);

  gst_element_class_set_details_simple(element_class,
    "Screen Capture Source (OSX)",
    "Source/Video",
    "Reads raw frames from a capture default Screen",
    "Artem Zaborskiy <artzab@avalon.ru>");

  gst_element_class_add_pad_template (element_class,
      gst_static_pad_template_get (&src_factory));
}

/* initialize the screencapturesrc's class */
static void
gst_screen_capture_src_class_init (GstScreenCaptureSrcClass * klass)
{
    GObjectClass *gobject_class = G_OBJECT_CLASS (klass);
    GstBaseSrcClass *gstbasesrc_class = GST_BASE_SRC_CLASS (klass);
    GstPushSrcClass *gstpushsrc_class = GST_PUSH_SRC_CLASS (klass);
    
    GST_DEBUG ("%s", G_STRFUNC);
    
    gobject_class->finalize = gst_screen_capture_src_finalize;
    gobject_class->get_property = gst_screen_capture_src_get_property;
    gobject_class->set_property = gst_screen_capture_src_set_property;
    
    gstbasesrc_class->set_caps = gst_screen_capture_src_set_caps;
    gstbasesrc_class->get_caps = gst_screen_capture_src_get_caps;
    gstbasesrc_class->start = gst_screen_capture_src_start;
    gstbasesrc_class->stop = gst_screen_capture_src_stop;
    gstbasesrc_class->get_times = gst_screen_capture_src_get_times;
    gstbasesrc_class->fixate = gst_screen_capture_src_fixate;
    
    gstpushsrc_class->create = gst_screen_capture_src_create;

    g_object_class_install_property (gobject_class, PROP_SHOW_CURSOR,
                                   g_param_spec_boolean ("cursor", "Show mouse cursor",
                                                         "Whether to show mouse cursor (default off)",
                                                         FALSE, G_PARAM_READWRITE));
    GST_DEBUG_CATEGORY_INIT (gst_screen_capture_src_debug, "screencapturesrc", 0,
                             "screencapturesrc source");
}

/* initialize the new element
 * instantiate pads and add them to element
 * set pad calback functions
 * initialize instance structure
 */
static void
gst_screen_capture_src_init (GstScreenCaptureSrc * src,
    GstScreenCaptureSrcClass * gclass)
{
    GST_DEBUG_OBJECT (src, "%s", G_STRFUNC);

    OBJC_CALLOUT_BEGIN ();
    src->impl = [[GstScreenCaptureSrcImpl alloc] initWithSrc:GST_PUSH_SRC (src)];
    OBJC_CALLOUT_END ();
}

static void
gst_screen_capture_src_finalize (GObject * obj)
{
    OBJC_CALLOUT_BEGIN ();
    [GST_SCREENCAPTURESRC_IMPL (obj) release];
    OBJC_CALLOUT_END ();
    
    G_OBJECT_CLASS (parent_class)->finalize (obj);
}

static void
gst_screen_capture_src_get_property (GObject * object, guint prop_id,
    GValue * value, GParamSpec * pspec)
{
  GstScreenCaptureSrcImpl *impl = GST_SCREENCAPTURESRC_IMPL (object);

  switch (prop_id) {
    case PROP_SHOW_CURSOR:
      g_value_set_boolean (value, impl.cursor);
      break;
    default:
      G_OBJECT_WARN_INVALID_PROPERTY_ID (object, prop_id, pspec);
      break;
  }
}

static void
gst_screen_capture_src_set_property (GObject * object, guint prop_id,
    const GValue * value, GParamSpec * pspec)
{
  GstScreenCaptureSrcImpl *impl = GST_SCREENCAPTURESRC_IMPL (object);

  switch (prop_id) {
    case PROP_SHOW_CURSOR:
      impl.cursor = g_value_get_boolean (value);
      break;
    default:
      G_OBJECT_WARN_INVALID_PROPERTY_ID (object, prop_id, pspec);
      break;
  }
}

/* GstElement vmethod implementations */

/* this function handles the link with other elements */
static gboolean
gst_screen_capture_src_set_caps (GstBaseSrc * basesrc, GstCaps * caps)
{
    gboolean ret;
    
    OBJC_CALLOUT_BEGIN ();
    ret = [GST_SCREENCAPTURESRC_IMPL (basesrc) setCaps:caps];
    OBJC_CALLOUT_END ();
    
    return ret;
}

static GstCaps 
*gst_screen_capture_src_get_caps (GstBaseSrc * basesrc)
{
    GstCaps *ret;
    
    OBJC_CALLOUT_BEGIN ();
    ret = [GST_SCREENCAPTURESRC_IMPL (basesrc) getCaps];
    OBJC_CALLOUT_END ();
    
    return ret;
};

static gboolean
gst_screen_capture_src_start (GstBaseSrc * basesrc)
{
    gboolean ret;
    
    OBJC_CALLOUT_BEGIN ();
    ret = [GST_SCREENCAPTURESRC_IMPL (basesrc) start1];
    OBJC_CALLOUT_END ();
    
    return ret;
}

static gboolean
gst_screen_capture_src_stop (GstBaseSrc * basesrc)
{
    gboolean ret;
    
    OBJC_CALLOUT_BEGIN ();
    ret = [GST_SCREENCAPTURESRC_IMPL (basesrc) stop];
    OBJC_CALLOUT_END ();
    
    return ret;
}

static void
gst_screen_capture_src_fixate (GstBaseSrc * basesrc, GstCaps * caps)
{
    OBJC_CALLOUT_BEGIN ();
    [GST_SCREENCAPTURESRC_IMPL (basesrc) fixate: caps];
    OBJC_CALLOUT_END ();
}

static void 
gst_screen_capture_src_get_times (GstBaseSrc * basesrc, GstBuffer * buffer, GstClockTime * start, GstClockTime * end)
{
    OBJC_CALLOUT_BEGIN ();
    [GST_SCREENCAPTURESRC_IMPL (basesrc) getTimes:buffer vStart:start vEnd:end];
    OBJC_CALLOUT_END ();
};

static GstFlowReturn
gst_screen_capture_src_create (GstPushSrc * pushsrc, GstBuffer ** buf)
{
    GstFlowReturn ret;
    
    OBJC_CALLOUT_BEGIN ();
    ret = [GST_SCREENCAPTURESRC_IMPL (pushsrc) create: buf];
    OBJC_CALLOUT_END ();
    
    return ret;
}
