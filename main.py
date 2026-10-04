# Based on the organizers' starter project (Hacktoberfest Hack Day Berlin 2026)
# Model switched from gemma4 to llama3.2 (smaller download)

from ai import ask_ai


inputtext = input("Describe a location:")
answer = ask_ai(f"""
Given a short description of a location for a Dungeons and Dragons campaign, come up with a unique Name, the inhabitants of that place and the name of a special item that can be found there.
Answer strictly in the following format without any headers or subtitles, seperated by commas: [Name], [Inhabitant/s], [Special item]. Prompt:{inputtext}""")

print(answer)
