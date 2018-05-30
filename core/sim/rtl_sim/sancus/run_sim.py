#!/usr/bin/env python

import argparse
import re
import math
import subprocess
import tempfile
import os

IHEX2MEM = '${FULL_INSTALL_TOOLS_PATH}/ihex2mem.tcl'
COMMANDS = '${FULL_INSTALL_SIM_PATH}/commands.f'

def _get_awidth(size):
    return int(math.ceil(math.log(size / 2.0, 2)))

def _parse_size(val):
    try:
        return int(val)
    except ValueError:
        match = re.match(r'(\d+)K', val)
        if not match:
            raise ValueError('Not a valid size expression: {}'.format(val))
        return int(match.group(1)) * 1024

def _run(prog, *args):
    cmd = [prog] + list(args)
    if cli_args.verbose:
        print ' '.join(cmd)
    try:
        subprocess.check_call(cmd)
    except:
        print 'Command failed'
        exit(1)

parser = argparse.ArgumentParser(description='Sancus simulator')
parser.add_argument('--ram-size',
                    type=_parse_size,
                    default='10K')
parser.add_argument('--rom-size',
                    type=_parse_size,
                    default='48K')
parser.add_argument('--verbose',
                    action='store_true')
parser.add_argument('in_file',
                    help='ELF file to run',
                    nargs=1)
cli_args = parser.parse_args()

ram_size = cli_args.ram_size
rom_size = cli_args.rom_size
in_file = cli_args.in_file[0]

ihex_file = tempfile.mkstemp('.ihex')[1]
_run('msp430-objcopy', '-O', 'ihex', in_file, ihex_file)

mem_file = tempfile.mkstemp('.mem')[1]
_run(IHEX2MEM, '-ihex', ihex_file, '-out', mem_file,
               '-mem_size', str(rom_size))

fd, sim_file = tempfile.mkstemp()
os.close(fd)
_run('iverilog', '-DMEM_DEFINED', '-DPMEM_SIZE_CUSTOM', '-DDMEM_SIZE_CUSTOM',
                 '-DPMEM_CUSTOM_SIZE={}'.format(rom_size),
                 '-DPMEM_CUSTOM_AWIDTH={}'.format(_get_awidth(rom_size)),
                 '-DDMEM_CUSTOM_SIZE={}'.format(ram_size),
                 '-DDMEM_CUSTOM_AWIDTH={}'.format(_get_awidth(ram_size)),
                 '-DPMEM_FILE="{}"'.format(mem_file),
                 '-f', COMMANDS, '-o', sim_file)

print 'Starting Verilog simulation. Press <Ctrl-C> to get to the Icarus ' + \
      'Verilog CLI, then "finish" to exit.'
os.execl(sim_file, sim_file)
