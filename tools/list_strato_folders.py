#!/usr/bin/env python3
"""Read-only list of IMAP mailboxes at STRATO (no passwords stored)."""
import getpass
import imaplib

username = input('STRATO email [r@example.nl]: ').strip() or 'r@example.nl'
password = getpass.getpass('STRATO IMAP password: ')
try:
    with imaplib.IMAP4_SSL('imap.strato.de', 993, timeout=20) as server:
        typ, _ = server.login(username, password)
        if typ != 'OK':
            raise RuntimeError('Login failed')
        typ, lines = server.list()  # LIST defaults: quoted "" reference and * pattern
        if typ != 'OK':
            raise RuntimeError('Could not list IMAP folders')
        print('\nFolders as returned by STRATO:')
        for line in lines or []:
            if line is not None:
                print(line.decode('utf-8', errors='replace'))
        print('\nFolder names should be copied exactly, including dots in nested names.')
except (imaplib.IMAP4.error, OSError) as error:
    raise SystemExit(f'IMAP error: {error}') from error
