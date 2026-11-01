#!/usr/bin/env python3
"""Check Mailu SMTP accepts an arbitrary From and forwards via STRATO.
Python 3 stdlib only. Use an external test inbox YOU control.
"""
import getpass
import smtplib
import socket
import ssl
from email.message import EmailMessage
from email.utils import formatdate, make_msgid

host=input('Your home server host/IP [127.0.0.1]: ').strip() or '127.0.0.1'
port=int(input('Mailu SMTP over SSL port [465]: ').strip() or '465')
user=input('LOCAL Mailu account [r@example.nl]: ').strip() or 'r@example.nl'
pwd=getpass.getpass('LOCAL Mailu account password (not STRATO password): ')
to=input('EXTERNAL destination inbox you control: ').strip()
if '@' not in to: raise SystemExit('Invalid recipient')
alias=input('Alias local-part for test [alias-demo]: ').strip() or 'alias-demo'
if not alias.replace('-','').replace('_','').isalnum(): raise SystemExit('Invalid alias local part')
sender=f'{alias}@{user.rsplit("@",1)[-1]}'
msg=EmailMessage()
msg['From']=sender
msg['To']=to
msg['Subject']='Local Mailu via STRATO catch-all From test'
msg['Date']=formatdate(localtime=True)
msg['Message-ID']=make_msgid(domain=user.rsplit('@',1)[-1])
msg.set_content('This test originated from Mailu and should be relayed by STRATO.\n')
# Intended for initial use with generated self-signed cert only.
context=ssl._create_unverified_context()
try:
    with smtplib.SMTP_SSL(host,port,timeout=20,context=context) as s:
        print('Connected:',s.noop())
        s.login(user,pwd)
        print('Authenticated. MAIL FROM:',sender)
        refused=s.send_message(msg,from_addr=sender,to_addrs=[to])
        print('SMTP submission:', 'ACCEPTED' if not refused else f'REFUSED {refused}')
        print('Check destination and Return-Path/From/DKIM headers. SMTP acceptance is not guaranteed delivery.')
except (smtplib.SMTPException,OSError,socket.timeout) as e:
    raise SystemExit(f'SMTP error: {e}') from e
