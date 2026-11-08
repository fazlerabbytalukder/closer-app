/**
 * "How well do you know me?" packs. Each question has exactly 4 options.
 * The subject picks the option that is true for them; the partner guesses.
 */
export interface GameQuestion {
  text: string;
  options: [string, string, string, string];
}

export interface GamePack {
  id: string;
  title: string;
  premium: boolean;
  questions: GameQuestion[];
}

export const QUESTIONS_PER_GAME = 5;

export const GAME_PACKS: Record<string, GamePack> = {
  starter: {
    id: "starter",
    title: "Starter",
    premium: false,
    questions: [
      {text: "My ideal weekend morning is…", options: ["Sleeping in", "Early workout", "Long breakfast", "Straight to plans"]},
      {text: "My go-to comfort food is…", options: ["Pizza", "Noodles", "Something sweet", "A home-cooked classic"]},
      {text: "On a free evening I'd rather…", options: ["Watch a series", "Go out with friends", "Read or game", "Try something new"]},
      {text: "My dream holiday is…", options: ["Beach", "City break", "Mountains", "Road trip"]},
      {text: "I'm most likely to be late because…", options: ["Overslept", "Couldn't pick an outfit", "Got distracted", "I'm never late"]},
      {text: "My favourite season is…", options: ["Spring", "Summer", "Autumn", "Winter"]},
      {text: "When I'm stressed I…", options: ["Go quiet", "Talk it out", "Keep busy", "Eat snacks"]},
      {text: "Pick my drink:", options: ["Coffee", "Tea", "Juice or smoothie", "Fizzy drink"]},
      {text: "My phone is usually at…", options: ["Under 20%", "Around half", "Fully charged", "Who knows, it's lost"]},
      {text: "My superpower would be…", options: ["Teleporting", "Flying", "Reading minds", "Stopping time"]},
      {text: "The chore I hate most is…", options: ["Dishes", "Laundry", "Vacuuming", "Grocery shopping"]},
      {text: "At a party you'll find me…", options: ["On the dance floor", "In the kitchen", "With the pets", "Leaving early"]},
      {text: "My music right now is mostly…", options: ["Pop", "Hip-hop / R&B", "Rock / indie", "Whatever the algorithm plays"]},
      {text: "I'd rather receive…", options: ["A handwritten note", "A surprise gift", "Quality time", "A big hug"]},
      {text: "My texting style is…", options: ["Lots of emojis", "Voice notes", "Short and sweet", "Essays"]},
      {text: "The animal I'd be is…", options: ["Cat", "Dog", "Owl", "Otter"]},
      {text: "My guilty pleasure show is…", options: ["Reality TV", "Cooking shows", "Anime", "True crime"]},
      {text: "When I travel I pack…", options: ["The night before", "A week early", "Way too much", "In ten minutes"]},
      {text: "I'm happiest when…", options: ["Outdoors", "With people I love", "Creating something", "Cosy at home"]},
      {text: "My breakfast is usually…", options: ["Skipped", "Cereal or toast", "Eggs", "Something fancy"]},
    ],
  },
  food: {
    id: "food",
    title: "Foodie",
    premium: true,
    questions: [
      {text: "Pineapple on pizza?", options: ["Yes, always", "Only sometimes", "Never", "Never tried it"]},
      {text: "My spice tolerance is…", options: ["Zero", "Mild", "Medium", "Bring the fire"]},
      {text: "Dessert of choice:", options: ["Ice cream", "Chocolate cake", "Fruit", "Pastries"]},
      {text: "My cooking skills are…", options: ["Microwave master", "Basic but fine", "Pretty good", "Chef level"]},
      {text: "I'd rather order…", options: ["Sushi", "Burgers", "Curry", "Tacos"]},
      {text: "My ideal snack is…", options: ["Crisps", "Nuts", "Sweets", "Cheese"]},
      {text: "Breakfast for dinner?", options: ["Love it", "Sometimes", "Weird", "Only pancakes"]},
      {text: "At a buffet I go for…", options: ["Everything", "Desserts first", "Salads", "Just one favourite"]},
    ],
  },
};
