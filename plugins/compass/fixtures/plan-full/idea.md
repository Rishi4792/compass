# Idea — compass-1-0
title: Compass 1.0

page: https://claude.ai/artifact/7mqJLUABiCUFQQt9bmxKf2
approved: 2026-10-26 by Rishi ("Yes, now let's simulate the building of this")
for: a person with an idea who directs AI to build it; not an engineer; maybe a first-time AI user
exists: Compass 0.35: 7,000 words to approve and its own rules to override · A chat window: no spec, no proof, no record
because: 0.35 has the rigour but asks you to read 7,000 words and override its own rules; a chat window has neither spec nor proof. Nothing else makes an AI build to spec and prove it live.
purpose: Describe what you want. Read one page. Say yes four times. Get a product that does what the page says, proven live.
hurts: Today a build means 7,137 words to approve an idea, 7 status files that disagree, 4 review rounds against a limit of 2, and 6 overrides asked of you in 3 days.
done: Two first-time users each ship a real build: no instructions, only /compass, 0 overrides, a live number beside every promise.

## Parts and promises
Each promise is one sentence a user could check, with its number.

## Journey
- phone: You type /compass
- chat: About eleven questions, like talking to a product head
- page: You read one page and say yes
- plan: I read your code and show the plan on one screen
- steps: I build part by part; you watch one card
- shield: Fresh reviewers try to break every promise
- rocket: It goes live; the real numbers land on your page

### Part 1 — One door
picture: phone
You type one command. It reads where you are, says so in one line, and asks one question.
- P1.1 Start a build by typing one command and answering questions. → 1 command · 0 instructions
- P1.2 Answer any question with "you decide"; every question shows its suggested answer and the reason. → 100% of questions
- P1.3 Start in an empty folder or inside an existing codebase. → 2 of 2 starts (empty folder, existing project)

### Part 2 — The Idea
picture: chat
A conversation like one with a product head. The page draws itself as you talk, and you approve it by reading it.
- P2.1 Finish the interview in about 10 questions, each with a suggested answer, including one or two that clarify the need and one that opens possibilities you had not considered. → ≈ 10 questions, 12 at most
- P2.2 Never be asked an engineering question. → 0 engineering questions
- P2.3 Read an Idea page with a picture per part and a number on every promise. → ≤ 150 words per part
- P2.4 Approve by reading the page. No form. No lock phrase. → 1 tap
- P2.5 For anything visual, approve a sketch before a word of code is written. → 1 picture before any code

### Part 3 — The Plan
picture: plan
The AI reads your code first, writes the plan the best teams write, and shows you one screen of it.
- P3.1 Read the plan on one screen: slices in order, the 3 biggest risks, any question for you. → 1 screen
- P3.2 Every step serves a promise; a step that serves none is deleted. → 100% traced
- P3.3 The skeleton is built first. → slice 1, always
- P3.4 Every plan cites real files from the code. → 0 uncited claims

### Part 4 — The Build
picture: steps
Part by part. Each step is built, proven by running, and recorded. The record is the only truth.
- P4.1 Close the laptop at any point; the build resumes from its record alone. → 0 lost steps
- P4.2 The card updates after every step, without asking. → 1 card update per step
- P4.3 Only promise checks and checks born from real breaks gate progress. → 0 extra tests
- P4.4 A step finishes in one sitting. → ≤ 1 session per step
- P4.5 Nothing is built that the Idea page does not say; a change goes through Change your mind first. → 0 silent changes

### Part 5 — Attacks
picture: shield
Fresh reviewers try to make each promise false, from Compass's own catalogue of the ways software fails.
- P5.1 Never see a review round, a findings list, or a severity label. → 0 rounds
- P5.2 Every break is fixed and attacked once more; then the attack is closed. → ≤ 2 attempts
- P5.3 Every check in the suite came from a real break of a real promise. → 100% born from breaks
- P5.4 Asked only when a promise still breaks after its second attempt: fix by hand, cut, or accept in writing. → 0 questions before a 2nd break

### Part 6 — Deploy
picture: rocket
Through your repo's own deploy path, with a restore point first. The real numbers are written back onto this page.
- P6.1 The live number sits next to every promise on the Idea page. → 1 live number per promise
- P6.2 The feature turns off with one switch, proven before launch, without a redeploy. → 1 switch
- P6.3 The whole release undoes with one rehearsed command. → 1 command
- P6.4 A plain-words release note; the watch period's end date is named and Compass runs the watch. → 1 end date, always named

### Part 7 — The Build Card
picture: card
One live page per build: where you are, one row per promise, your decisions, and the one question that needs you.
- P7.1 "Where are we and what is left" answered from one place, on a phone, in under 10 seconds. → 1 place
- P7.2 Asked at most four times per build (idea, plan, leftovers, deploy) plus true product choices. → ≤ 4 gates
- P7.3 Every decision made, with its date, in one list. → 100% of decisions, dated
- P7.4 No other status file exists; everything else is generated from the record or gone. → 0 other files

### Part 8 — Change your mind
picture: pencil
Edit one part of the Idea page. Only that part is re-planned and re-built. The rest stays proven.
- P8.1 Change the goal of one part without starting a new build. → 0 new builds
- P8.2 Only the edited part is attacked again; proven parts stay proven. → 1 part moves
- P8.3 The change is recorded on the card as a decision, with the date. → 1 dated line per change

## Never
fixed budgets per slice · prompts to extend time · review rounds · findings ledgers · typed lock phrases · a 7-stage strip · 59 self-test scripts · questions about rollback, flags or databases · a failure list the user must write · tests the AI chose on its own

## The one test that says the rebuild worked
Two people who have never used Compass each ship a real build. They read no instructions. They type only `/compass`. They are never asked to override a rule. Their Idea page shows a live number next to every promise.
