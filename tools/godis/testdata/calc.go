package main

type Parser struct {
	input string
	pos   int
}

func newParser(s string) *Parser {
	return &Parser{input: s, pos: 0}
}

func (p *Parser) peek() int {
	if p.pos >= len(p.input) {
		return 0
	}
	b := p.input[p.pos]
	return int(b)
}

func (p *Parser) next() int {
	ch := p.peek()
	p.pos = p.pos + 1
	return ch
}

func (p *Parser) parseNumber() int {
	n := 0
	for {
		ch := p.peek()
		if ch < 48 || ch > 57 {
			break
		}
		p.next()
		n = n*10 + (ch - 48)
	}
	return n
}

func (p *Parser) parseFactor() int {
	ch := p.peek()
	if ch == 40 { // '('
		p.next()
		val := p.parseExpr()
		p.next() // skip ')'
		return val
	}
	return p.parseNumber()
}

func (p *Parser) parseTerm() int {
	val := p.parseFactor()
	for {
		ch := p.peek()
		if ch == 42 { // '*'
			p.next()
			val = val * p.parseFactor()
		} else if ch == 47 { // '/'
			p.next()
			val = val / p.parseFactor()
		} else {
			break
		}
	}
	return val
}

func (p *Parser) parseExpr() int {
	val := p.parseTerm()
	for {
		ch := p.peek()
		if ch == 43 { // '+'
			p.next()
			val = val + p.parseTerm()
		} else if ch == 45 { // '-'
			p.next()
			val = val - p.parseTerm()
		} else {
			break
		}
	}
	return val
}

func eval(expr string) int {
	p := newParser(expr)
	return p.parseExpr()
}

func main() {
	println(eval("(3+4)*2"))
	println(eval("10-3"))
	println(eval("2*3+4*5"))
}
