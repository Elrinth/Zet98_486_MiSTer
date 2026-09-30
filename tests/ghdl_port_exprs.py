"""Copy FDC.vhd / FDemu.vhd with port-map expressions moved into signals.

GHDL 1.0 (mcode) crashes elaborating port associations such as
`bitlen => a/2` or `sel => not SRT` (trans.adb:553). Quartus accepts them,
so only the simulation copies change.
usage: ghdl_port_exprs.py in.vhd out.vhd
"""
import re, sys

src = open(sys.argv[1], newline='').read()
decls, assigns = [], []


def type_of(name):
    m = (re.search(r'^\s*signal\s+(?:\w+\s*,\s*)*' + name + r'\b(?:\s*,\s*\w+)*\s*:\s*([^;:=]+)', src, re.M | re.I) or
         re.search(r'^\s*' + name + r'\s*:\s*in\s+([^;:=]+)', src, re.M | re.I))
    return m.group(1).strip()


def lift(m):
    name = f'ghdl_port_expr{len(decls) + 1}'
    expr = m.group(2)
    operand = re.match(r'(?:not\s+)?(\w+)', expr).group(1)
    kind = type_of(operand) if expr.startswith('not') else 'integer'
    decls.append(f'signal {name} : {kind};\n')
    assigns.append(f'\t{name} <= {expr};\n')
    return m.group(1) + name + m.group(3)


# named associations (not generics: maxbwidth/2) and a positional first actual
src = re.sub(r'(=>\s*)((?:not\s+\w+)|(?:(?!maxbwidth)\w+/2))(\s*[,)])', lift, src)
src = re.sub(r'(port map\()(\w+/2)(,)', lift, src)
arch = re.search(r'^architecture\s+\w+\s+of\s+\w+\s+is\s*\n', src, re.M | re.I)
begin = arch.end() + re.search(r'^begin\s*\n', src[arch.end():], re.M).start()
src = src[:begin] + ''.join(decls) + src[begin:]
begin += len(''.join(decls))
at = begin + re.match(r'begin\s*\n', src[begin:]).end()
src = src[:at] + ''.join(assigns) + src[at:]
open(sys.argv[2], 'w', newline='').write(src)
