import requests
from bs4 import BeautifulSoup
import json
import sys
import getpass
from urllib.parse import urlparse, parse_qs

LOGIN_URL = "https://lsf.htw-berlin.de/qisserver/rds?state=user&type=1&category=auth.login&startpage=portal.vm"

def fetch_and_parse_lsf(username, password, target_week="14_2026"):
    PRINT_TIMETABLE_URL = f"https://lsf.htw-berlin.de/qisserver/rds?state=wplan&week={target_week}&act=show&pool=&show=plan&P.vx=mittel&P.Print="

    with requests.Session() as session:
        session.headers.update({
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
        })

        sys.stderr.write("1. Attempting login...\n")
        login_payload = {
            'asdf': username,        
            'fdsa': password,        
            'submit': 'Anmelden'
        }

        post_response = session.post(LOGIN_URL, data=login_payload)

        if "Anmelden" in post_response.text and "Startseite" in post_response.text and "Logout" not in post_response.text:
             sys.stderr.write("Login failed. Check credentials.\n")
             return None

        sys.stderr.write("Login successful! Session cookies stored.\n")

        sys.stderr.write(f"2. Fetching print view for week {target_week}...\n")
        timetable_response = session.get(PRINT_TIMETABLE_URL)

        sys.stderr.write("3. Parsing HTML into JSON...\n")
        soup = BeautifulSoup(timetable_response.text, 'html.parser')
        schedule_data = []

        # Find all cells starting with 'plan' that aren't structural layout cells
        event_cells = soup.find_all('td', class_=lambda c: c and c.startswith('plan') and c not in ['plan_rahmen', 'plan5', 'plan6', 'plan7', 'plan9'])

        for cell in event_cells:
            # A single time slot cell can contain multiple overlapping events.
            # We find all title links and process them individually.
            title_tags = cell.find_all('a', class_='ver')
            
            # Check if there's more than one title link in the cell
            is_overlapping = len(title_tags) > 1
            
            for title_tag in title_tags:
                # Extract Publish ID from the href URL
                href = title_tag.get('href', '')
                parsed_url = urlparse(href)
                publish_id = parse_qs(parsed_url.query).get('publishid', [None])[0]

                # Find the container for THIS specific event.
                # LSF wraps individual overlapping events in their own nested <table>.
                event_container = None
                for parent in title_tag.parents:
                    if parent == cell:
                        break # We reached the cell boundary
                    if parent.name == 'table':
                        event_container = parent
                        break
                        
                if not event_container:
                    event_container = cell

                # Check if it is an Exam
                is_exam = False
                warnung_spans = event_container.find_all('span', class_='warnung')
                for span in warnung_spans:
                    if 'Prüfung' in span.get_text():
                        is_exam = True
                        break
                
                event_dict = {
                    "publishId": publish_id,
                    "title": title_tag.get_text(strip=True),
                    "isExam": is_exam,
                    "isOverlapping": is_overlapping,
                    "day": None,
                    "time": None,
                    "room": None,
                    "type": None,
                    "frequency": None,
                    "raw_extras": []
                }

                # 2. Extract Details from .notiz cells specific to this event
                notiz_cells = event_container.find_all('td', class_='notiz')
                for n_cell in notiz_cells:
                    text = n_cell.get_text(separator=' ', strip=True)
                    
                    # Check if this line contains the room and type
                    if "Raum:" in text:
                        parts = text.split("Raum:")
                        event_dict["room"] = parts[1].strip()
                        
                        type_parts = parts[0].split(",")
                        if type_parts:
                            event_dict["type"] = type_parts[0].strip()
                    
                    # Check if this line contains the day and time (looking for typical formats)
                    elif ":" in text and "-" in text and "," in text:
                        # Example format: "Donnerstag, 08:00 - 09:30 , wöch"
                        time_parts = text.split(",")
                        if len(time_parts) >= 2:
                            event_dict["day"] = time_parts[0].strip()
                            event_dict["time"] = time_parts[1].strip()
                        if len(time_parts) >= 3:
                            event_dict["frequency"] = time_parts[2].strip()
                    else:
                        # Catch-all for SWS, language, or other notes
                        if text:
                            event_dict["raw_extras"].append(text)

                # Fix: Indented to be inside the title_tags loop!
                schedule_data.append(event_dict)

        return json.dumps(schedule_data, indent=4, ensure_ascii=False)

if __name__ == "__main__":
    week_number = input("Enter week number: ")
    target_week = f"{week_number}_2026"
    username = input("Enter HTW Username: ")
    password = getpass.getpass("Enter HTW Password: ")
    
    json_output = fetch_and_parse_lsf(username, password, target_week)
    
    if json_output:
        # Print the clean JSON to stdout
        print(json_output)