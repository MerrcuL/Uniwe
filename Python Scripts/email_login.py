import requests
from bs4 import BeautifulSoup
import getpass
import sys

# Start directly at the currentNG instance to get a valid CSRF token for that specific path
LOGIN_URL = "https://webmail.htw-berlin.de/currentNG/"

def get_webmail_cookies(username, password):
    with requests.Session() as session:
        # Standard browser headers (No Origin/Referer needed based on your browser trace)
        session.headers.update({
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
        })

        sys.stderr.write("1. Fetching login page to extract CSRF tokens...\n")
        response = session.get(LOGIN_URL)
        soup = BeautifulSoup(response.text, 'html.parser')

        login_form = soup.find('form')
        if not login_form:
            sys.stderr.write("Could not find the login form.\n")
            return None

        # 1. Extract all hidden fields (Crucial for Roundcube's '_token')
        payload = {}
        for input_tag in login_form.find_all('input', type='hidden'):
            name = input_tag.get('name')
            value = input_tag.get('value', '')
            if name:
                payload[name] = value

        # 2. Map the credentials
        payload['_user'] = username
        payload['_pass'] = password
        payload['login_username'] = username
        payload['secretkey'] = password
        
        # Explicitly declare the task and action
        payload['_task'] = 'login'
        payload['_action'] = 'login'

        # 3. Resolve the POST URL
        post_url = "https://webmail.htw-berlin.de/currentNG/?_task=login"

        sys.stderr.write("2. Attempting login POST request...\n")
        
        # --- NEW LOGGING ---
        sys.stderr.write(f"--- Payload being sent to {post_url} ---\n")
        safe_payload = payload.copy()
        safe_payload['_pass'] = '********'
        safe_payload['secretkey'] = '********'
        for k, v in safe_payload.items():
             sys.stderr.write(f"  {k}: {v}\n")
        sys.stderr.write("----------------------------------------\n")
        # -------------------

        # We set allow_redirects=False to catch the 302 Found exactly like your browser trace
        post_response = session.post(post_url, data=payload, allow_redirects=False)

        # Verification: A successful login returns a 302 redirecting to ?_task=mail
        if post_response.status_code == 302 and "_task=mail" in post_response.headers.get('Location', ''):
            sys.stderr.write("Login successful! 302 Redirect caught. Webmail cookies stored.\n")
            
            # The session automatically stores the new rcube_htw_sessauth cookie
            cookies_dict = session.cookies.get_dict()
            return cookies_dict
        else:
            sys.stderr.write("Login failed. Check credentials or token extraction.\n")
            sys.stderr.write(f"\n--- Debug Info ---\n")
            sys.stderr.write(f"Response Status Code: {post_response.status_code}\n")
            sys.stderr.write(f"Location Header (if any): {post_response.headers.get('Location')}\n")
            sys.stderr.write("------------------\n")
            return None

if __name__ == "__main__":
    user = input("Enter HTW Username: ")
    pw = getpass.getpass("Enter HTW Password: ")
    
    cookies = get_webmail_cookies(user, pw)
    if cookies:
        print("\n--- Extracted Session Cookies ---")
        import json
        print(json.dumps(cookies, indent=4))


'''
1. Fetching login page to extract CSRF tokens...
2. Attempting login POST request...
--- Payload being sent to https://webmail.htw-berlin.de/currentNG/?_task=login ---
  _token: kdoqEOQ7ifCUfWlcg4sJzQIbqdPRdIYK
  _task: login
  _action: login
  _timezone: _default_
  _url:
  login_username: s0601985
  secretkey: ********
  _user: s0601985
  _pass: ********
----------------------------------------
Login successful! 302 Redirect caught. Webmail cookies stored.

--- Extracted Session Cookies ---
{
    "rcube_htw_sessauth": "5696f07qje80ng1ufioooec077",
    "rcube_htw_sessid": "DTudpzBnynv3h4q0rjGamZSFr8-1775822400"
}
'''        