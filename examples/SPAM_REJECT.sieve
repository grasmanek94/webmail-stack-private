# Paste into Roundcube > Settings > Filters > raw Sieve editor.
# First create an IMAP folder named SPAM_REJECT in Roundcube.
# This moves mail locally; it does NOT reject email back to sender.
require ["fileinto", "regex", "imap4flags"];

if address :regex ["To", "Cc"] "^(mediamarkt|marktplaats)@gz0\\.nl$" {
    fileinto "SPAM_REJECT";
    stop;
}

# Flag messages to politie@example.nl
if address :is ["To", "Cc"] "politie@example.nl" {
    addflag "\\Flagged";
    keep;
    stop;
}
