import requests
from bs4 import BeautifulSoup
import json
import sys
import getpass

LOGIN_URL = "https://lsf.htw-berlin.de/qisserver/rds?state=user&type=1&category=auth.login&startpage=portal.vm"

def fetch_lecture_details(username, password, publish_id="231534"):
    DETAIL_URL = f"https://lsf.htw-berlin.de/qisserver/rds?state=verpublish&status=init&vmfile=no&publishid={publish_id}&moduleCall=webInfo&publishConfFile=webInfo&publishSubDir=veranstaltung"

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

        sys.stderr.write(f"2. Fetching details for publish_id {publish_id}...\n")
        detail_response = session.get(DETAIL_URL)
        html_text = detail_response.text

        # 3. HTML lokal speichern fürs Debugging
        filename = f"lecture_details_{publish_id}.html"
        with open(filename, "w", encoding="utf-8") as file:
            file.write(html_text)
        sys.stderr.write(f"--> Saved raw HTML to '{filename}'.\n\n")

        # 4. Parsing the HTML based on actual LSF structure
        soup = BeautifulSoup(html_text, 'html.parser')
        details = {
            "publishId": publish_id,
            "credits": None,
            "sws": None,
            "teachers": [],
            "exam_dates": []
        }

        # Extract Grunddaten (Credits, SWS)
        # Look for table cells containing the exact labels
        for label in soup.find_all(['th', 'td']):
            text = label.get_text(strip=True)
            if text == "Credits":
                next_td = label.find_next_sibling('td')
                if next_td:
                    details["credits"] = next_td.get_text(strip=True)
            elif text == "SWS":
                next_td = label.find_next_sibling('td')
                if next_td:
                    details["sws"] = next_td.get_text(strip=True)

        # Extract Termine (Teachers, Exams)
        # Find the table that contains "Lehrperson" in its headers
        schedule_tables = soup.find_all('table')
        for table in schedule_tables:
            headers = [th.get_text(strip=True) for th in table.find_all('th')]
            
            if "Lehrperson" in headers:
                # Map column indices based on headers to be robust against layout changes
                try:
                    day_idx = headers.index("Tag")
                    time_idx = headers.index("Zeit")
                    duration_idx = headers.index("Dauer")
                    teacher_idx = headers.index("Lehrperson")
                    remark_idx = headers.index("Bemerkung")
                except ValueError:
                    # If standard headers are missing, skip this table
                    continue

                for tr in table.find_all('tr'):
                    cells = tr.find_all('td')
                    
                    # Ensure the row has enough columns
                    if len(cells) > max(day_idx, time_idx, duration_idx, teacher_idx, remark_idx):
                        teacher = cells[teacher_idx].get_text(strip=True)
                        remark = cells[remark_idx].get_text(strip=True)
                        
                        # Clean up teacher string and avoid duplicates
                        if teacher and teacher not in details["teachers"]:
                            details["teachers"].append(teacher)
                            
                        # Find exams by checking the remarks column
                        if "Prüfung" in remark:
                            exam_info = {
                                "day": cells[day_idx].get_text(strip=True),
                                "time": cells[time_idx].get_text(strip=True),
                                "date": cells[duration_idx].get_text(strip=True).replace("am ", "")
                            }
                            
                            # Avoid duplicate exam entries
                            if exam_info not in details["exam_dates"]:
                                details["exam_dates"].append(exam_info)

        return json.dumps(details, indent=4, ensure_ascii=False)

if __name__ == "__main__":
    test_id = input("Enter publishid (e.g., 231534): ")
    username = input("Enter HTW Username: ")
    password = getpass.getpass("Enter HTW Password: ")
    
    json_output = fetch_lecture_details(username, password, test_id)
    
    if json_output:
        print(json_output)