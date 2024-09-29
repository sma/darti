import 'dart:io';
import 'dart:math';

int year = 1;
int population = 100;
int grain = 2800;
int acres = 1000;
final random = Random();

void main() {
  print('Welcome to the game of Hammurabi!');
  print('Manage the city-state of Babylon for 10 years.\n');

  while (year <= 10 && population > 0) {
    printStatus();
    int acresToBuy = askHowManyAcresToBuy();
    int acresToSell = askHowManyAcresToSell();
    int grainToFeed = askHowMuchGrainToFeed();
    int acresToPlant = askHowManyAcresToPlant();

    updateCity(acresToBuy, acresToSell, grainToFeed, acresToPlant);
    year++;
  }

  endGame();
}

void printStatus() {
  print('\nYear $year');
  print('Population: $population');
  print('Acres: $acres');
  print('Grain: $grain bushels');
}

int askHowManyAcresToBuy() {
  int price = random.nextInt(10) + 17;
  print('\nLand is trading at $price bushels per acre.');
  return getIntInput('How many acres do you wish to buy? ');
}

int askHowManyAcresToSell() {
  return getIntInput('How many acres do you wish to sell? ');
}

int askHowMuchGrainToFeed() {
  return getIntInput('How many bushels do you wish to feed your people? ');
}

int askHowManyAcresToPlant() {
  return getIntInput('How many acres do you wish to plant with seed? ');
}

int getIntInput(String prompt) {
  while (true) {
    print(prompt);
    String? input = stdin.readLineSync();
    if (input != null) {
      // try {
      return int.parse(input);
      // } catch (e) {
      //   print('Please enter a valid number.');
      // }
    }
  }
}

void updateCity(int acresToBuy, int acresToSell, int grainToFeed, int acresToPlant) {
  int landPrice = random.nextInt(10) + 17;

  grain -= acresToBuy * landPrice;
  grain += acresToSell * landPrice;
  acres += acresToBuy - acresToSell;

  int peopleStarved = calculateStarvation(grainToFeed);
  int peopleArrived = random.nextInt(5) + 1;

  population += peopleArrived - peopleStarved;

  int harvest = (random.nextInt(5) + 1) * acresToPlant;
  grain += harvest;

  if (random.nextInt(100) < 15) {
    int grainEatenByRats = (grain * (random.nextInt(3) + 1) ~/ 10);
    grain -= grainEatenByRats;
    print('Rats ate $grainEatenByRats bushels of grain!');
  }
}

int calculateStarvation(int grainToFeed) {
  int peopleStarved = population - grainToFeed ~/ 20;
  if (peopleStarved > 0) {
    print('$peopleStarved people starved to death.');
    return peopleStarved;
  }
  return 0;
}

void endGame() {
  print('\nGame Over!');
  if (population <= 0) {
    print('The entire population has died. You were a terrible ruler!');
  } else {
    print('You have completed your 10-year term as ruler of Babylon.');
    print('Final population: $population');
    print('Final grain stores: $grain bushels');
    print('Final land holdings: $acres acres');
  }
}
