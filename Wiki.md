Project 03: Navigating Without Sight

Team and roles
| Member      | Role(s)                               |
| S     -> Project Manager, Implementation Lead |
| C      -> Research Lead, Evaluation Lead       |
| A      ->                          |
| A      ->                  |
| I      -> Design Lead                          |


## Project idea

Most story games only care about the button you press. They don't know if you hesitated, got nervous or felt calm. We want to see what happens when a game can notice how you feel and changes the story because of it.

We are building a short interrogation game. You play someone being questioned by a detective about a stolen painting. A webcam estimates whether you look calm, anxious or scared, and the game reacts. The detective changes how he speaks, the answers you are offered change, the lighting in the room shifts, and the story can end in different ways. Halfway through, a clock falls off the wall, which gives us a small startle to see how the game and the player react.

The game reads your face on your own computer. The video is never saved or sent anywhere, and only numbers are logged.

The main question is not whether the technology works, because webcam emotion reading is far from perfect. It is whether it matters that players know about it. So we made three versions of the same game:

- **A:** buttons only, with no emotion sensing.
- **B:** the game reads your face and adapts, but doesn't tell you.
- **C:** the game reads your face, shows you what it thinks you feel, lets you correct it, and lets you switch it off.

We are being open about what is real and what is simulated. The emotion guess is a simple rule based on facial expression scores, not a true reading of feelings. The story is short and scripted, and we say so in our limitations.

## Users and scenarios

**Users:** people who play narrative or story-driven games. For the study our participants will mostly be classmates (18 or older), which we will note as a limitation, since they are not a perfect sample of all players.

We also care about what the players think about privacy. Emotion data is sensitive, so some people may not want a game watching their face, and we want to know how they feel about that.

**Scenario A: the interrogation.** A player sits down with the game and is questioned by the detective. They answer within a time limit, and their face is read while they answer. If they look calm, the detective becomes suspicious. If they look scared, he becomes gentler or offers a deal. Later, the clock falls, and how they react changes what the detective says next. The player reaches one of several endings.

**Scenario B: noticing and taking control.** The player realises the game is responding to them, perhaps because the detective comments on their expression, and wants to understand why. In version C they can see what the game thinks they feel, correct it when it is wrong, or turn the sensing off and keep playing. In version B they can't see any of this, which is the point of the comparison.

## Research question

Does showing players what the game thinks they feel, and letting them correct it or switch it off, improve their enjoyment, sense of control and trust, compared with a game that reacts to their emotion in secret or ignores it?

To answer this we will compare the three versions (A, B and C) with the same participants. We plan to look at:

- how much they enjoyed the game
- how much control they felt they had
- how much they trusted the game
- whether they felt watched
- how often the game's guess matched what players said they felt

We will report the accuracy honestly. If the guess is wrong a lot, that is a result too.

## Timeline

| Week starting | What we do | Who |
|---------------|-----------|-----|
| 26 Oct | Choose the brief, set up the GitHub repo and wiki, agree roles, write the first plan | S, C |
| 2 Nov | Research: related work and existing games, short survey of possible users, write requirements | C |
| 9 Nov | Design: sketches of the story and the three conditions, test the paper version with a few people | I |
| 16 Nov | Prototype v1: first playable version of the interrogation game, pilot with a classmate. Presentation 2 on Tue 17 Nov | S, C |
| 23 Nov | Prototype v2: webcam tracking, branching story, the falling clock, fullscreen, endings and logging. Start on consent form and questionnaires | S, C |
| 30 Nov | Finish study materials, first user tests, look at the data and decide what to change. Slides due Mon 30 Nov, Presentation 3 on Tue 1 Dec | C |
| 7 Dec | Main study with at least 5 participants (aiming for 10), analysis, final fixes | C, S|
| 14 Dec | Final slides due Mon 14 Dec, final presentation Tue 15 Dec, finish README, tag the final version | C, S |
| Fri 18 Dec | Final delivery: code and report (max 12 pages) | Everyone |

**Risks:** webcam tracking may behave differently on the Ubuntu lab computers, so we test there every week. If we can't recruit enough participants we start early with classmates. If the face tracking is too unreliable, we can fall back on a hidden team member giving the emotion labels (Wizard of Oz) and say so clearly.
