import 'package:closer_app/core/models/models.dart';

/// Question packs. In production these live in `content/questionPacks` and
/// are picked by the `assignDailyQuestions` function; the local backend uses
/// this bundled copy.
class QuestionPack {
  const QuestionPack({
    required this.id,
    required this.title,
    required this.emoji,
    required this.description,
    required this.questions,
    this.plus = false,
    this.adultsOnly = false,
    this.modes = const {PairMode.couple, PairMode.friends},
  });

  final String id;
  final String title;
  final String emoji;
  final String description;
  final List<String> questions;
  final bool plus;
  final bool adultsOnly;
  final Set<PairMode> modes;
}

const questionPacks = <QuestionPack>[
  QuestionPack(
    id: 'everyday',
    title: 'Everyday',
    emoji: '☀️',
    description: 'Light, fun questions for every day.',
    questions: [
      "What's a small thing that made you smile today?",
      'If we could teleport anywhere for dinner tonight, where would we go?',
      "What song is stuck in your head right now?",
      'What would your perfect lazy Sunday look like?',
      "What's one thing you're looking forward to this week?",
      'Which snack could you eat every day forever?',
      "What's the best thing you've watched lately?",
      'If you had a free afternoon tomorrow, how would you spend it?',
      "What's a skill you'd love to learn this year?",
      'Coffee, tea, or something else entirely?',
      "What's a memory of us that always makes you laugh?",
      'Beach holiday or mountain cabin?',
      "What's your comfort meal after a long day?",
      'If you could swap lives with anyone for a day, who would it be?',
      'What emoji describes your week so far?',
      "What's something you're proud of lately?",
      'Which fictional world would you most want to live in?',
      "What's the last photo you took — and why?",
      'Morning person or night owl? Be honest.',
      'What would be the title of a movie about your life right now?',
      "What's a tiny luxury that's totally worth it?",
      'If we started a business together, what would it be?',
      "What's a place from your childhood you still think about?",
      'Which season matches your personality?',
      "What's the best gift you've ever received?",
      'If you could master one instrument overnight, which one?',
      "What's a habit you'd like to start?",
      'What three things would you bring to a desert island?',
      "What's something you've changed your mind about recently?",
      'What would you do with an extra hour every day?',
    ],
  ),
  QuestionPack(
    id: 'deep',
    title: 'Deep talk',
    emoji: '🌙',
    description: 'Slower questions for the long conversations.',
    plus: true,
    questions: [
      'When do you feel most like yourself?',
      "What's something you've never told anyone but would like to?",
      'What does a good life look like to you in 10 years?',
      'Which moment changed the way you see the world?',
      'What are you still learning to forgive yourself for?',
      'How do you know when you feel truly cared for?',
      'What fear would you like to let go of?',
      'What tradition would you like us to start?',
      "What's a dream you've quietly put on hold?",
      'What do you think people misunderstand about you?',
    ],
  ),
  QuestionPack(
    id: 'long-distance',
    title: 'Long distance',
    emoji: '✈️',
    description: 'For when there are miles in between.',
    plus: true,
    questions: [
      "What's the first thing we'll do when we see each other next?",
      'What part of my day do you wish you could see?',
      "What's something that reminds you of me where you are?",
      'Which time zone moment do you like most?',
      'If you could mail me one thing tomorrow, what would it be?',
      "What's our next trip together going to be?",
      'What would a perfect video call date look like?',
      'Which song makes the distance feel smaller?',
    ],
  ),
  QuestionPack(
    id: 'bff',
    title: 'Best friends',
    emoji: '👯',
    description: 'Made for best friends.',
    plus: true,
    modes: {PairMode.friends},
    questions: [
      'What was your first impression of me?',
      'Which inside joke of ours is the best?',
      'What would our friendship be as a TV show?',
      "What's a trip we absolutely have to take?",
      'Which of us would survive longer in a zombie movie?',
      "What's the most 'us' thing we've ever done?",
      'What song would play when we walk into a room together?',
      'What advice from me actually helped you?',
    ],
  ),
  QuestionPack(
    id: 'spicy',
    title: 'Spicy',
    emoji: '🌶️',
    description: 'Flirty questions for couples. 18+ only.',
    plus: true,
    adultsOnly: true,
    modes: {PairMode.couple},
    questions: [
      'What did you first find attractive about me?',
      "What's your idea of a perfect date night in?",
      'What outfit of mine is your favourite?',
      'Where would you take me for a surprise weekend away?',
      "What's the most romantic thing I've done for you?",
      'Describe our first kiss in three words.',
      "What's something you'd like us to try together?",
      'When do you find me most irresistible?',
    ],
  ),
];

QuestionPack packById(String id) =>
    questionPacks.firstWhere((p) => p.id == id, orElse: () => questionPacks.first);

/// "How well do you know me?" question bank.
const knowMeQuestions = <GameQuestion>[
  GameQuestion(text: 'My ideal weekend is…', options: ['Adventure outdoors', 'Couch + series', 'Seeing friends', 'A spontaneous trip']),
  GameQuestion(text: 'My go-to comfort food is…', options: ['Pizza', 'Pasta', 'Sushi', 'Something sweet']),
  GameQuestion(text: 'If I won the lottery, first I would…', options: ['Travel the world', 'Buy a house', 'Quit my job', 'Give a lot away']),
  GameQuestion(text: 'My biggest pet peeve is…', options: ['Lateness', 'Loud chewing', 'Slow walkers', 'Messy rooms']),
  GameQuestion(text: 'On a night out I am most likely…', options: ['On the dance floor', 'Chatting at the bar', 'Leaving early', 'Organising everyone']),
  GameQuestion(text: 'My dream pet would be…', options: ['A dog', 'A cat', 'Something exotic', 'No pets, thanks']),
  GameQuestion(text: 'I would rather…', options: ['Read the book', 'Watch the movie', 'Listen to the podcast', 'Skip it']),
  GameQuestion(text: 'My favourite season is…', options: ['Spring', 'Summer', 'Autumn', 'Winter']),
  GameQuestion(text: 'When stressed I usually…', options: ['Go for a walk', 'Eat snacks', 'Talk it out', 'Sleep']),
  GameQuestion(text: 'My hidden talent is…', options: ['Cooking', 'Singing', 'Remembering everything', 'Making people laugh']),
  GameQuestion(text: 'The superpower I would choose is…', options: ['Flying', 'Teleporting', 'Mind reading', 'Pausing time']),
  GameQuestion(text: 'My morning starts with…', options: ['Coffee', 'Phone scrolling', 'Exercise', 'Snoozing 5 times']),
  GameQuestion(text: 'My favourite way to say "I care" is…', options: ['Words', 'Gifts', 'Doing things for you', 'Quality time']),
  GameQuestion(text: "I'd most like to visit…", options: ['Japan', 'Iceland', 'Italy', 'New Zealand']),
  GameQuestion(text: 'In a group project I am…', options: ['The leader', 'The ideas person', 'The quiet worker', 'The one who forgets']),
];

/// Moods and status presets (F6).
const moodOptions = <(String, String)>[
  ('😊', 'Happy'),
  ('🥰', 'Loved'),
  ('😴', 'Sleepy'),
  ('🤒', 'Sick'),
  ('😤', 'Stressed'),
  ('🥳', 'Excited'),
  ('😢', 'Sad'),
  ('🤯', 'Busy'),
  ('😌', 'Calm'),
  ('🤤', 'Hungry'),
  ('🥶', 'Cold'),
  ('🫠', 'Tired'),
];

const statusPresets = <String>[
  'At work 💼',
  'Studying 📚',
  'At the gym 🏋️',
  'Commuting 🚆',
  'Cooking 🍳',
  'With friends 🍻',
  'Watching something 🍿',
  'Going to sleep 🌙',
  'Thinking of you 💭',
  'Do not disturb 🔕',
];
