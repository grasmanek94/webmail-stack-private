<?php
// Applied by the official Roundcube Docker image after its generated configuration.
// TLS peer checking is disabled ONLY for internal Docker-network connections to
// Mailu's self-signed certificate. End users connect to nginx over HTTPS.
$config['imap_conn_options'] = [
    'ssl' => ['verify_peer' => false, 'verify_peer_name' => false, 'allow_self_signed' => true]
];
$config['smtp_conn_options'] = [
    'ssl' => ['verify_peer' => false, 'verify_peer_name' => false, 'allow_self_signed' => true]
];
$config['smtp_user'] = '%u';
$config['smtp_pass'] = '%p';
$config['managesieve_host'] = 'tls://front';
$config['managesieve_port'] = 4190;
$config['managesieve_conn_options'] = [
    'ssl' => ['verify_peer' => false, 'verify_peer_name' => false, 'allow_self_signed' => true]
];
$config['managesieve_raw_editor'] = true;
// Catch-all replies: first same-domain address in To:, then Cc:, then delivery headers.
$config['custom_from_compose_auto'] = true;
$config['custom_from_compose_contains'] = '@example.nl';
$config['custom_from_compose_identity'] = 'loose';
$config['custom_from_preference_disable'] = true;
$config['custom_from_header_rules'] = 'To=d;Cc=d;X-Original-To=d;Envelope-To=d;Delivered-To=d';
