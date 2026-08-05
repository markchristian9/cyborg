# Cyborg

- It is an action RPG game
- It is an MMORPG. Many players share the same live world at the same time.


## Workflow

You, as AI, must follow the instructions below.

- [ ] Git commit & push after work
- [ ] 작업이 끝난 다음 "/cowork:cowork ..." 를 통해서 수정 보완 작업을 해 주세요.

## Overview

- AI Robot conquered the world, Human cyborg fight back to save the world.

## References

- 형제 게임 라리엔: ` ~/apps/game/laryen` 폴더를 보고, 라리엔 게임의 로직/코드를 바탕으로 기능/코드를 복사해와도 됩니다. 단, 절대로 라리엔 게임 소스 코드를 수정해서는 안됩니다. 반드시, ` ~/apps/game/laryen` 폴더는 읽기 전용으로만 참고해야 합니다.



## World

- One open world map. Every player plays on that single shared map.
- No per-match instance, no separated stage. Players join the world, not a session.


## Multiplayer

- Multiple users must be able to join the world and play in it at the same time.
- A party travels and hunts together, and **shares experience**.
  Kill credit itself stays solo: the first attacker owns the monster, and the
  loot and the kill record go to that owner alone. There is no shared damage
  credit and no party loot rule.
- Experience from a kill is split among party members who were within 30 tiles
  of where the monster fell, alive, and in the same party. The total grows with
  headcount (+10% per extra member, so 2.1x at twelve), is divided evenly, and
  is then scaled per member by how close their level is to the monster's level
  (full within 10 levels, then 50% / 25% / nothing). The owner is exempt from
  that scaling and keeps the division remainder. A party member hunting alone
  earns exactly what they would solo.
- Party members may follow their leader. A follower auto-hunts around the leader
  and shares in every kill the group lands nearby.
- Monsters are still shared world objects. A monster one player kills is dead
  for everyone, and the kill belongs to a single player.
- Other players' presence, movement and combat must be visible to each other in real time.
- PK is allowed. A PC can attack another PC. Party membership grants no protection —
  it shares position and a follow anchor, nothing else. Contesting a tagged monster
  still means fighting its owner.


## Tech Stack

- Flutter and Flame to build 2.5d isometric game.
- SpacetimeDB for the backend.


## Debugging and Testing

- Always test with DTD. Do not test the game by running and injecting/emulating the typeing or click becuase the human developer is always actively using computer and keyboard.
- Always inject the test code/function/event-handler into main() or initState() to move the page or run the event handler.
  - For instance, to login, inject login email/password on the inputs and call the event handler of login.
- Take screenshots or check logs to debug and test.


