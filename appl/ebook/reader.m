
# the public interface to this looks like:
#	Reader: module {
#		PATH: con "/dis/ebook/reader.dis";
#		init: fn(displ: ref Draw->Display);
#		Datasource: adt {
#			new:		fn(f: string, win: ref Tk->Toplevel, width: int, evch: string): (ref Datasource, string);
#			copy:	fn(d: self ref Datasource): ref Datasource;
#			mark:	fn(d: self ref Datasource): ref Mark;
#			goto:	fn(d: self ref Datasource, m: ref Mark);
#			atmark:	fn(d: self ref Datasource, m: ref Mark): int;
#			next:		fn(d: self ref Datasource, linkch: chan of (string, string, string)): string;
#	
#			linestart:	fn(d: self ref Datasource, w: string, y: int): int;
#			linkoffset:	fn(d: self ref Datasource, w: string, s: string): int;
#		};
#	};


Reader: module {
	PATH: con "/dis/ebook/reader.dis";
	init: fn(displ: ref Draw->Display);
	Datasource: adt {
		x:		ref Xml->Parser;
		t:		ref Text;
		title:		string;
		win:		ref Tk->Toplevel;
		evch:	string;			# tk channel on which to send events
		tags:		list of ref Xml->Item.Tag;
		width:	int;
		filename:	string;
		error:	string;
		item:		ref Xml->Item;
		imark:	ref Xml->Mark;		# mark at start of item
		fontinfo:	list of ref Fontinfo;
		styles:	list of ref Stylesheet->Style;
		stylesheet:	ref Stylesheet->Sheet;
		linkch:	chan of (string, string, string);		# (linkname, widgetname, internal reference)
		warningch: chan of (Xml->Locator, string);
		startmark:	ref Reader->Mark;	# mark start of body for copy()
		fallbacks:	list of (string, string);

		# public interface consists solely of the following few methods, along with the Mark adt.
		new:		fn(f: string, fallbacks: list of (string, string), win: ref Tk->Toplevel, width: int, evch: string, warningch: chan of (Xml->Locator, string)): (ref Datasource, string);
		copy:	fn(d: self ref Datasource): ref Datasource;
		mark:	fn(d: self ref Datasource): ref Mark;
		str2mark:	fn(d: self ref Datasource, s: string): ref Mark;
		mark2str:	fn(d: self ref Datasource, m: ref Mark): string;
		goto:	fn(d: self ref Datasource, m: ref Mark);
		atmark:	fn(d: self ref Datasource, m: ref Mark): int;
		next:		fn(d: self ref Datasource, linkch: chan of (string, string, string)): (Block, string);
		fileoffset:	fn(d: self ref Datasource): int;

		rectforfileoffset:	fn(t: self ref Datasource, w: string, fileoffset: int): (int, Draw->Rect);
		fileoffsetnearyoffset:	fn(t: self ref Datasource, w: string, yoffset: int): int;
		linestart:	fn(d: self ref Datasource, w: string, y: int): int;
		linkoffset:	fn(d: self ref Datasource, w: string, s: string): int;
		event:	fn(d: self ref Datasource, e: string): ref Event;
	};

	Block: adt {
		w: string;
		tmargin, bmargin: int;
	};

	Event: adt {
		pick {
		Link =>
			url:	string;
		Texthit =>
			fileoffset:	int;
		}
	};
		
	Mark: adt {
		xmark:	ref Xml->Mark;
		eq:	fn(m1: self ref Mark, m2: ref Mark): int;
		fileoffset:	fn(m: self ref Mark): int;
	};

	Text: adt {
		win:		ref Tk->Toplevel;
		w:		string;
		tags:		array of list of (string, int);	# hash of (attrs, tagnum); holds all currently used tags in widget
		max:		int;			# max tagnum
		href:		string;
		margins:		list of Margin;		# margins of enclosing blocks
		margin:		Margin;			# current margin values
		outertmargin:	int;
		outerbmargin:	int;
		needspace:	int;			# vspace waiting
		lastwhite:		int;			# did the last text hold trailing whitespace?
		startofline:	int;
		style:	ref Stylesheet->Style;
		fontinfo:	ref Fontinfo;
		evch:	string;

		new:		fn(win: ref Tk->Toplevel, w: string, width: int, evch: string): ref Text;
		addtext:	fn(t: self ref Text, text: string, ws1, ws2: int, fileoffset: int);
		gettag:	fn(t: self ref Text,  s: string): string;
		linebreak:	fn(t: self ref Text);
		addmark:	fn(t: self ref Text): string;
		widgetname:	fn(t: self ref Text, t: int): string;
		addwidget:	fn(t: self ref Text, w: string, fileoffset: int, invisible: int);
		startblock:	fn(t: self ref Text);
		endblock:		fn(t: self ref Text);
		finalise:	fn(t: self ref Text, addvspace: int);
		vspace:	fn(t: self ref Text, h: int);
	};

	Margin: adt {
		l, r, b, textindent: int;
	};

	Fontinfo: adt {
		path:		string;
		em:		int;
		ex:		int;
	};
};
