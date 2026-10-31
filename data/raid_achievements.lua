-- Galar Rising's achievements for the recomp_achievements framework (provider "max_raids").
-- Rows are the framework's definition fields: id (a-z 0-9 _ -, never changed), title (32),
-- description (160), points (0..100), goal + unit (a counter), hidden, category (16). Text is plain
-- ASCII. src/achievements.lua reports against these ids.

return {
  list = {
    { id = "first_den", title = "Into the Den", points = 5, category = "RAIDS",
      description = "Walk up to a den and press A to look inside for the first time." },
    { id = "first_raid", title = "Raid Rookie", points = 5, category = "RAIDS",
      description = "Win your first raid." },
    { id = "go_big", title = "Go Big", points = 5, category = "RAIDS",
      description = "Dynamax a Pokemon in a raid." },
    { id = "gotcha_giant", title = "Gotcha, Giant!", points = 5, category = "RAIDS",
      description = "Catch the Pokemon from a raid." },
    { id = "untouched", title = "Untouched", points = 10, category = "RAIDS",
      description = "Win a raid without a single Pokemon of yours fainting." },
    { id = "den_delver", title = "Den Delver", points = 10, category = "RAIDS",
      goal = 25, unit = "RAIDS", description = "Win 25 raids." },
    { id = "gigantamax", title = "Gigantamax!", points = 10, category = "RAIDS",
      description = "Gigantamax a Pokemon in a raid. Pokemon caught from Gigantamax raids have the factor." },
    { id = "giant_slayer", title = "Giant Slayer", points = 10, category = "RAIDS",
      description = "Defeat a Gigantamax Pokemon from a purple den." },
    { id = "five_star", title = "Five-Star General", points = 25, category = "RAIDS",
      description = "Win a 5-star raid." },
    { id = "gallery", title = "Gigantamax Gallery", points = 25, category = "RAIDS",
      goal = 10, unit = "BOSSES", description = "Defeat 10 different Gigantamax bosses in raids." },
    { id = "crystal_clear", title = "Crystal Clear", points = 25, category = "RAIDS",
      description = "Win a legendary raid started with a Dynamax Crystal." },
    { id = "shiny_raider", title = "Shiny Raider", points = 25, category = "RAIDS",
      description = "Catch a shiny Pokemon from a raid." },
    { id = "quick_work", title = "Quick Work", points = 10, category = "RAIDS", hidden = true,
      description = "Win a raid against a 3-star or stronger boss in 3 turns or fewer." },
    { id = "blown_away", title = "Blown Away", points = 5, category = "RAIDS", hidden = true,
      description = "Run from a raid and get blown out of the den." },
  },

  -- Quick Work: a win in this many turns or fewer, against a boss of at least this many stars
  QUICK = { TURNS = 3, MIN_STARS = 3 },
}
