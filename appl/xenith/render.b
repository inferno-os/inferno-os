implement Render;

include "sys.m";
	sys: Sys;

include "draw.m";
	draw: Draw;
	Display, Image: import draw;

include "renderer.m";
include "render.m";

display: ref Display;

# Cached renderer modules: avoid reloading the same .dis repeatedly
CachedRenderer: adt {
	modpath: string;
	mod: Renderer;
};

entries: list of ref RendererEntry;
cache: list of ref CachedRenderer;

init(d: ref Draw->Display)
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	display = d;
	entries = nil;
	cache = nil;

	# Register built-in renderers
	register("/dis/xenith/render/imgrender.dis");
	register("/dis/xenith/render/mdrender.dis");
	register("/dis/xenith/render/htmlrender.dis");
	register("/dis/xenith/render/pdfrender.dis");
}

# Load and cache a renderer module
loadrenderer(modpath: string): (Renderer, string)
{
	# Check cache first
	for(cl := cache; cl != nil; cl = tl cl){
		c := hd cl;
		if(c.modpath == modpath)
			return (c.mod, nil);
	}

	# Load the module
	mod := load Renderer modpath;
	if(mod == nil)
		return (nil, sys->sprint("cannot load renderer %s: %r", modpath));

	mod->init(display);

	# Cache it
	cache = ref CachedRenderer(modpath, mod) :: cache;
	return (mod, nil);
}

register(modpath: string): string
{
	(mod, err) := loadrenderer(modpath);
	if(mod == nil)
		return err;

	ri := mod->info();
	if(ri == nil)
		return "renderer returned nil info";

	# Check for duplicate
	for(el := entries; el != nil; el = tl el){
		e := hd el;
		if(e.modpath == modpath)
			return nil;  # Already registered
	}

	entry := ref RendererEntry(ri.name, modpath, ri.extensions, 0);
	entries = entry :: entries;
	return nil;
}

# Extract file extension from path (lowercase)
getext(path: string): string
{
	if(path == nil)
		return nil;
	dot := -1;
	for(i := len path - 1; i >= 0; i--){
		c := path[i];
		if(c == '.'){
			dot = i;
			break;
		}
		if(c == '/')
			break;
	}
	if(dot < 0)
		return nil;

	ext := path[dot:];
	# Lowercase
	buf := "";
	for(i = 0; i < len ext; i++){
		c := ext[i];
		if(c >= 'A' && c <= 'Z')
			c += 'a' - 'A';
		buf[len buf] = c;
	}
	return buf;
}

# Check if ext is in a space-separated extension list
extmatch(ext: string, extlist: string): int
{
	if(ext == nil || extlist == nil)
		return 0;

	# Split on spaces and check each
	(nil, toks) := sys->tokenize(extlist, " ");
	for(; toks != nil; toks = tl toks){
		if(hd toks == ext)
			return 1;
	}
	return 0;
}

find(data: array of byte, path: string): (Renderer, string)
{
	ext := getext(path);

	# Phase 1: find by extension
	bestmod: Renderer;
	bestpri := -1;

	for(el := entries; el != nil; el = tl el){
		e := hd el;
		if(extmatch(ext, e.extensions)){
			if(e.priority > bestpri){
				(mod, err) := loadrenderer(e.modpath);
				if(mod != nil){
					bestmod = mod;
					bestpri = e.priority;
				}
			}
		}
	}

	if(bestmod != nil)
		return (bestmod, nil);

	# Phase 2: probe all renderers with canrender()
	if(data != nil){
		bestconf := 0;
		for(el = entries; el != nil; el = tl el){
			e := hd el;
			(mod, err) := loadrenderer(e.modpath);
			if(mod != nil){
				conf := mod->canrender(data, path);
				if(conf > bestconf){
					bestmod = mod;
					bestconf = conf;
				}
			}
		}
		if(bestmod != nil)
			return (bestmod, nil);
	}

	return (nil, "no renderer for " + path);
}

findbyext(path: string): (Renderer, string)
{
	return find(nil, path);
}

getall(): list of ref RendererEntry
{
	return entries;
}

iscontent(path: string): int
{
	ext := getext(path);
	if(ext == nil)
		return 0;

	for(el := entries; el != nil; el = tl el){
		e := hd el;
		if(extmatch(ext, e.extensions))
			return 1;
	}
	return 0;
}
