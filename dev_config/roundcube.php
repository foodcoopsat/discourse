<?php

$config['cipher_method'] = 'AES-256-CBC';
$config['enable_spellcheck'] = true;
$config['identities_level'] = 1;
$config['log_driver'] = 'stdout';
$config['managesieve_host'] = 'tls://srv01.foodcoops.at';
$config['oauth_auth_uri'] = "https://app.local.at/discourse-virtmail/oauth2/authorize";
$config['oauth_client_id'] = "roundcube";
$config['oauth_client_secret'] = file_get_contents('/run/secrets/roundcube_oauth_client_secret');
$config['oauth_identity_uri'] = "https://app.local.at/discourse-virtmail/oauth2/introspect.json";
$config['oauth_provider_name'] = 'Forum';
$config['oauth_provider'] = 'generic';
$config['oauth_scope'] = "email";
$config['oauth_token_uri'] = "https://app.local.at/discourse-virtmail/oauth2/token.json";
$config['plugins'] = [];
$config['product_name'] = 'FoodCoops Österreich Webmail';
$config['skin_logo'] = '/images/foodcoops_logo.png';
$config['spellcheck_engine'] = 'pspell';
$config['use_https'] = true;
$config['zipdownload_selection'] = true;
