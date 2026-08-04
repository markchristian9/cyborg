# Cyborg

- It is an action RPG game
- It is an MMORPG. Many players share the same live world at the same time.


## Workflow

You, as AI, must follow the instructions below.

- [ ] Git commit & push after work
- [ ] 작업이 끝난 다음 "/cowork:cowork ..." 를 통해서 수정 보완 작업을 해 주세요.

## Overview

- AI Robot conquered the world, Human cyborg fight back to save the world.


## World

- One open world map. Every player plays on that single shared map.
- No per-match instance, no separated stage. Players join the world, not a session.


## Multiplayer

- Multiple users must be able to join the world and play in it at the same time.
- Hunting is solo, not party based. There is no party, no shared damage credit
  and no party loot rule. Each player hunts monsters on their own.
- Monsters are still shared world objects. A monster one player kills is dead
  for everyone, and the kill belongs to a single player.
- Other players' presence, movement and combat must be visible to each other in real time.
- PK is allowed. A PC can attack another PC.


## Tech Stack

- Flutter and Flame to build 2.5d isometric game.
- SpacetimeDB for the backend.


## Debugging and Testing

- Always test with DTD. Do not test the game by running and injecting/emulating the typeing or click becuase the human developer is always actively using computer and keyboard.
- Always inject the test code/function/event-handler into main() or initState() to move the page or run the event handler.
  - For instance, to login, inject login email/password on the inputs and call the event handler of login.
- Take screenshots or check logs to debug and test.


