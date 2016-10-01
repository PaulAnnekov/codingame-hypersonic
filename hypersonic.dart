import 'dart:io';
import 'dart:math';

int range = 3;
int countdown = 8;
List<Point> directions = [new Point(1, 0), new Point(0, 1),
    new Point(-1, 0), new Point(0, -1)];

void main() {
    Logger.level = LogLevels.DEBUG;
    var game = new Game();
    game.start();
}

Map<dynamic, Map> cloneMapOfMaps(Map<dynamic, Map> from) {
    var newMap = {};
    for (var key in from.keys) {
        newMap[key] = new Map.from(from[key]);
    }
    return newMap;
}

class GameMap {
    List<List<String>> map = [];
    int width;
    int height;

    void updateFromInput() {
        map.clear();
        for (int i = 0; i < height; i++) {
            var a = stdin.readLineSync();
            Logger.info(a);
            map.add(a.split(''));
        }
    }

    bool isOutOfMap(int x, int y) {
        return x < 0 || y < 0 || y >= height || x >= width;
    }

    Map cellType(Point cell) {
        var val = map[cell.y][cell.x];
        return {
            'obstacle': val != '.',
            'box': int.parse(val, onError: (_) => null) != null,
            'free': val == '.',
            'wall': val == 'X'
        };
    }

    GameMap clone() {
        var newMap = new GameMap();
        newMap.map = [];
        map.forEach((row) {
            newMap.map.add(new List.from(row));
        });
        newMap.width = width;
        newMap.height = height;
        return newMap;
    }

    String toString() {
        String out = '    ';
        for (var i = 0; i < width; i++)
            out += i.toString().padRight(2) + ' ';
        out += '\n\n';
        var i = 0;
        map.forEach((line) {
            out += i.toString().padRight(2) + '  ' + line.join('  ');
            out += '\n';
            i++;
        });
        return out;
    }
}

class ComplexCheck {
    GameMap _map;
    BombsWatcher _bombsWatcher;

    ComplexCheck(this._map, this._bombsWatcher);

    bool isObstacle(Point cell) {
        return _map.isOutOfMap(cell.x, cell.y) || _map.cellType(cell)['obstacle'] || _bombsWatcher.isBomb(cell);
    }
}

class Game {
    Map<int, Map> players = {};
    int myId;
    Point target, targetPos, myLocation;
    GameMap map;
    BombsWatcher bombsWatcher;
    Map targetType = {'box': true};
    String nextAction;
    Point nextStep;
    AStar aStar;
    ComplexCheck complexChecker;
    int lastEnemyBomb = 0;
    int maxBombs = 1;

    void start() {
        map = new GameMap();
        _readInput();
        Stopwatch watch = new Stopwatch();
        while (true) {
            watch.reset();
            watch.start();
            _loop();
            Logger.debug('loop ms: ${watch.elapsedMilliseconds}');
        }
    }

    void _readInput() {
        List inputs = stdin.readLineSync().split(' ');
        map.width = int.parse(inputs[0]);
        map.height = int.parse(inputs[1]);
        myId = int.parse(inputs[2]);
    }

    void _readEntities() {
        players.clear();
        bombsWatcher = new BombsWatcher(map);
        int entities = int.parse(stdin.readLineSync());
        for (int i = 0; i < entities; i++) {
            List inputs = stdin.readLineSync().split(' ');
            int entityType = int.parse(inputs[0]);
            int owner = int.parse(inputs[1]);
            Point pos = new Point(int.parse(inputs[2]), int.parse(inputs[3]));
            int param1 = int.parse(inputs[4]);
            int param2 = int.parse(inputs[5]);
            if (entityType == 0) {
                players[owner] = {'pos': pos, 'bombs': param1, 'range': param2};
            } else if (entityType == 1) {
                bombsWatcher.addBomb(pos, {'owner': owner, 'countdown': param1,
                    'range': param2});
            } else if (entityType == 2) {
                bombsWatcher.addBonus(pos, param1);
            }
        }
    }

    void _checkSettle() {
        if (target != null && myLocation == target &&
            players[myId]['bombs'] > 0 && targetType['box']) {
            Logger.info('settled a BOMB');
            bombsWatcher.addBomb(target, {
                'owner': myId,
                'countdown': countdown,
                'range': players[myId]['range']
            });
            players[myId]['bombs']--;
            nextAction = 'BOMB';
            target = null;
        }
    }

    /*Map _getNextTarget(int step, Point _myLocation) {
        var affectedBoxes = bombsWatcher.getAffectedBoxes(step);
        // if no target or target already destroyed or to be destroyed - find new target
        Logger.debug('searching');
        var spiralProcessor = new SpiralProcessor(bombsWatcher.mapAtStep(step), _myLocation);
        var box, boxes = {};
        var aStar = new AStar(bombsWatcher.mapAtStep(step), bombsWatcher);
        while ((box = spiralProcessor.getNext()) != null) {
            Logger.debug('box near ${box}');
            if (affectedBoxes.contains(box)) {
                Logger.info("it's marked as 'to destroy'");
                continue;
            }
            var path = aStar.path(myLocation, box);
            if (path == null)
                continue;
            var stepsToFreeBomb = bombsWatcher.stepsToFreeBomb(myId, maxBombs);
            if (bombsWatcher.isDeadPos(path[1], stepsToFreeBomb-path.length-1, stepsToFreeBomb)) {
                Logger.info('we will die if wait at ${path[1]}');
                continue;
            }
            boxes[path.length] = {'path': path};
        }
        var targetBox;
        // if not the last box where we settled a bomb and no more boxes.
        if (boxes.isNotEmpty) {
            var distances = boxes.keys.toList();
            Logger.debug('boxes ${boxes}, distances ${distances}');
            distances.sort();
            targetBox = boxes[distances[0]];
        }
        if (targetBox != null) {
            target = targetBox['path'][1];
            targetPos = targetBox['path'][0];
            // path <= 2 means we are right near target
            nextStep = targetBox['path'].length > 2 ? targetBox['path'][targetBox['path'].length - 2] : myLocation;
            Logger.info('target ${target}');
            Logger.info('toDestroy ${targetPos}');
            Logger.info('nextStep ${nextStep}');
        } else {
            nextAction = 'MOVE';
            target = null;
        }
    }*/

    void _checkTarget() {
        var affectedBoxes = bombsWatcher.getAffectedBoxes();
        // if no target or target already destroyed or to be destroyed - find new target
        Logger.debug('searching');
        var spiralProcessor = new SpiralProcessor(map, myLocation);
        var box, boxes = {};
        while ((box = spiralProcessor.getNext()) != null) {
            Logger.debug('box near ${box}');
            if (affectedBoxes.contains(box)) {
                Logger.info("it's marked as 'to destroy'");
                continue;
            }
            var path = aStar.path(myLocation, box);
            if (path == null)
                continue;
            var stepsToFreeBomb = bombsWatcher.stepsToFreeBomb(myId, maxBombs);
            if (stepsToFreeBomb > 0 && bombsWatcher.isDeadPos(path[1], stepsToFreeBomb-path.length-1, stepsToFreeBomb)) {
                Logger.info('we will die if wait at ${path[1]}');
                continue;
            }
            boxes[path.length] = {'path': path};
        }
        var targetBox;
        // if not the last box where we settled a bomb and no more boxes.
        if (boxes.isNotEmpty) {
            var distances = boxes.keys.toList();
            Logger.debug('boxes ${boxes}, distances ${distances}');
            distances.sort();
            targetBox = boxes[distances[0]];
            // TODO: replace with next step calc
            while (distances.isNotEmpty) {
                var checkBox = boxes[distances.first];
                var checkStep = checkBox['path'][checkBox['path'].length-2];
                Logger.debug('_checkDeadLock ${checkStep}');
                if (bombsWatcher.isBomb(myLocation) && _checkDeadLock(checkStep)) {
                    distances.removeAt(0);
                    Logger.debug('locked ${distances}');
                    targetBox = null;
                    nextStep = null;
                } else {
                    targetBox = checkBox;
                    break;
                }
            }
        }
        if (targetBox != null) {
            target = targetBox['path'][1];
            targetPos = targetBox['path'][0];
            // path <= 2 means we are right near target
            nextStep = targetBox['path'].length > 2 ? targetBox['path'][targetBox['path'].length - 2] : myLocation;
            Logger.info('target ${target}');
            Logger.info('toDestroy ${targetPos}');
            Logger.info('nextStep ${nextStep}');
        } else {
            nextAction = 'MOVE';
            target = null;
        }
    }

    bool _checkDeadLock(Point pos) {
        List<Point> directionsClone = new List.from(directions);
        var target;
        for (var direction in directions) {
            // don't check back direction
            if (pos + direction == myLocation) {
                directionsClone.remove(direction);
                target = new Point(direction.x * -1, direction.y * -1);
                directionsClone.remove(target);
                break;
            }
        }
        if (directionsClone.length > 2)
            throw new Exception('Only 2 directions must exist ${pos}, ${myLocation}');
        Logger.debug('directions: ${directionsClone}');
        while (!complexChecker.isObstacle(pos)) {
            var choices = 0, cell;
            for (var direction in directionsClone) {
                cell = pos + direction;
                if (complexChecker.isObstacle(cell))
                    continue;
                Logger.debug('free: ${cell}');
                choices++;
            }
            if (choices > 0)
                return false;
            pos += target;
            Logger.debug('new pos: ${pos}');
        }
        return true;
    }

    void _checkOnFire() {
        Logger.debug('_checkOnFire ${nextStep}');
        var fireSides = bombsWatcher.isOnFire(nextStep);
        if (fireSides.isEmpty)
            return;
        var currentFireSides = bombsWatcher.isOnFire(myLocation);
        if (currentFireSides.isNotEmpty) {
            List<List<int>> directions = [[1, 0], [0, 1], [-1, 0], [0, -1]];
            var choices = [];
            directions.forEach((direction) {
                var choice = new Point(
                    myLocation.x + direction[0], myLocation.y + direction[1]);
                if (map.isOutOfMap(choice.x, choice.y))
                    return;
                var type = map.cellType(choice);
                if (currentFireSides.contains(choice) || type['obstacle'] ||
                    bombsWatcher.isBomb(choice))
                    return;
                choices.add(choice);
            });
            if (choices.isEmpty) {
                Logger.info('you are doomed');
            } else {
                nextStep = choices[0];
            }
        } else {
            nextStep = myLocation;
        }
    }

    void _checkEnemy() {
        if (target != null)
        {
            lastEnemyBomb = 0;
            return;
        }
        lastEnemyBomb--;
        var haveBombs = players[myId]['bombs'] > 0;
        Map tmp = new Map.from(players);
        tmp.remove(myId);
        var path = aStar.path(myLocation, tmp[tmp.keys.first]['pos']);
        nextStep = path != null && path.length > 2 ? path[path.length-2] : myLocation;
        if (haveBombs && lastEnemyBomb <= 0 && path != null && path.length <= 3)
        {
            nextAction = 'BOMB';
            lastEnemyBomb = 3;
        }
    }

    void _loop() {
        Logger.info('loop');
        map.updateFromInput();
        _readEntities();
        complexChecker = new ComplexCheck(map, bombsWatcher);
        aStar = new AStar(map, bombsWatcher);
        myLocation = players[myId]['pos'];
        Logger.debug('before algo');
        targetType = targetPos != null ? map.cellType(targetPos) : null;
        nextAction = null;
        _checkSettle();
        _checkTarget();
        _checkEnemy();
        _checkOnFire();
        if (bombsWatcher.isBonusBombNextStep(nextStep))
            maxBombs++;
        print((nextAction != null ? nextAction : 'MOVE') +
            ' ${nextStep.x} ${nextStep.y}');
        Logger.debug('end');
    }
}

class BombsWatcher {
    static final List<List<int>> directions = [[1, 0], [0, 1], [-1, 0], [0, -1]];
    Map<int, GameMap> _mapPerStep = {};
    Map<int, Map<Point, Map>> _bombsPerStep = {};
    Map<int, Map<Point, int>> _bonusesPerStep = {};
    Map<int, List<Point>> _fireCellsPerStep = {};

    BombsWatcher(GameMap map) {

        _bombsPerStep[0] = {};
        _bonusesPerStep[0] = {};
        _mapPerStep[0] = map;
    }

    void addBomb(Point pos, Map info) {
        _bombsPerStep[0][pos] = info;
    }

    void addBonus(Point pos, int type) {
        _bonusesPerStep[0][pos] = type;
    }

    Map<String, List<Point>> _getAffected(Point pos, Map info, int step, {Point custom}) {
        var map = _mapPerStep[step];
        var bombs = _bombsPerStep[step];
        var bonuses = _bonusesPerStep[step];
        Map<String, List<Point>> affected = {'boxes': [], 'bombs': [], 'bonuses': [], 'cells': []};
        // we check bomb position because it can be on bonus
        if (bonuses.containsKey(pos))
            affected['bonuses'].add(pos);
        directions.forEach((direction) {
            for (var i = 1; i < info['range']; i++) {
                var cell = new Point(
                    pos.x + direction[0] * i, pos.y + direction[1] * i);
                if (map.isOutOfMap(cell.x, cell.y))
                    break;
                var type = map.cellType(cell);
                // wall blocks fire
                if (type['wall'])
                    break;
                // TODO: use Set type?
                affected['cells'].add(cell);
                if (type['box']) {
                    affected['boxes'].add(cell);
                    break;
                }
                if (bombs.containsKey(cell)) {
                    affected['bombs'].add(cell);
                    break;
                }
                if (bonuses.containsKey(cell)) {
                    affected['bonuses'].add(cell);
                    break;
                }
            }
        });

        return affected;
    }

    bool isBomb(Point pos) {
        return _bombsPerStep[0].containsKey(pos);
    }

    bool isBonusBombNextStep(Point pos) {
        _calcStep(1);
        var bonus = _bonusesPerStep[1][pos];
        // we check next step, because bonus can be destroyed before we step on it
        return bonus != null && bonus == 2;
    }

    int stepsToFreeBomb(int owner, int maxBombs) {
        var step = 0, bombs;
        do {
            bombs = _bombsPerStep[step].values.where((bomb) => bomb['owner'] == owner).length;
            step++;
            _calcStep(step);
        } while (bombs >= maxBombs);
        step--;
        return step;
    }

    bool isDeadPos(Point pos, int stepFrom, int stepTo) {
        for (var i = 1; i <= stepTo; i++) {
            _calcStep(i);
            if (i >= stepFrom && _fireCellsPerStep[i].contains(pos)) {
                return true;
            }
        }
        return false;
    }

    void _calcStep(int step) {
        if (_mapPerStep[step] != null)
            return;
        var prevMap = _mapPerStep[step-1].clone();
        var prevBombs = cloneMapOfMaps(_bombsPerStep[step-1]);
        var prevBonuses = new Map.from(_bonusesPerStep[step-1]);
        var fireCells = [];
        var queue = prevBombs.keys.toList();
        _mapPerStep[step] = prevMap;
        _bombsPerStep[step] = prevBombs;
        _bonusesPerStep[step] = prevBonuses;
        _fireCellsPerStep[step] = fireCells;
        while (queue.isNotEmpty) {
            var bombPos = queue.first;
            var bomb = prevBombs[queue.first];
            bomb['countdown']--;
            if (bomb['countdown'] == 0) {
                var affected = _getAffected(bombPos, bomb, step);
                affected['boxes'].forEach((pos) {
                    var box = int.parse(prevMap.map[pos.y][pos.x]);
                    if (box > 0)
                        prevBonuses[pos] = box;
                    prevMap.map[pos.y][pos.x] = '.';
                });
                affected['bombs'].forEach((pos) {
                    var affectedBomb = prevBombs[pos];
                    affectedBomb['countdown'] = 1;
                    if (!queue.contains(pos))
                        queue.add(pos);
                });
                affected['bonuses'].forEach((pos) {
                    prevBonuses.remove(pos);
                });
                fireCells.addAll(affected['cells']);
                prevMap.map[bombPos.y][bombPos.x] = '.';
                prevBombs.remove(bombPos);
            }
            queue.removeAt(0);
        }
        /*Logger.debug('step: ${step}');
        Logger.debug(prevMap);
        Logger.debug(prevBombs);
        Logger.debug(prevBonuses);*/
    }

    /**
     * Is point will be destroyed on next step.
     */
    List<Point> isOnFire(Point point) {
        List<Point> sides = [];
        for (var pos in _bombsPerStep[0].keys) {
            var info = _bombsPerStep[0][pos];
            if (info['countdown'] > 2)
                continue;
            var isKill = false;
            for (var direction in directions) {
                for (var i = 0; i < info['range']; i++) {
                    var cell = new Point(
                        pos.x + direction[0] * i, pos.y + direction[1] * i);
                    if (_mapPerStep[0].isOutOfMap(cell.x, cell.y))
                        break;
                    var type = _mapPerStep[0].cellType(cell);
                    // wall blocks fire
                    if (type['wall'])
                        break;
                    if (cell == point) {
                        Logger.debug('bomb ${pos} will kill you at ${cell}');
                        sides.add(new Point(
                            cell.x - direction[0], cell.y - direction[1]));
                        // fire can strike us from both sides
                        if (info['range'] > i + 1) {
                            sides.add(new Point(
                                cell.x + direction[0], cell.y + direction[1]));
                        }
                        isKill = true;
                        break;
                    }
                }
                if (isKill)
                    break;
            };
            if (sides.length > 3)
                break;
        };
        return sides;
    }

    GameMap mapAtStep(int step) {
        for (var i = 1; i <= step; i++) {
            _calcStep(i);
        }
        return _mapPerStep[step];
    }

    List<Point> getAffectedBoxes([int step = 0]) {
        for (var i = 1; i <= step; i++) {
            _calcStep(i);
        }
        List<Point> boxes = [];
        _bombsPerStep[step].forEach((pos, info) {
            boxes.addAll(_getAffected(pos, info, step)['boxes']);
        });
        return boxes;
    }
}

class SpiralProcessor {
    Point _current;
    Point _point;
    int radius = 1;
    bool _isEnd = false;
    double _angle = 0.0;
    Map _cellsPerLoop = {};
    GameMap _map;

    SpiralProcessor(GameMap map, Point point) {
        _point = point;
        _map = map;
    }

    Point getNext() {
        bool isFound = false;
        while (!_isEnd) {
            var _angleFactor = PI / 2 / (radius * 2);
            _cellsPerLoop[radius] ??= 0;
            while (_angle < 2 * PI) {
                var x = _point.x + _nearest(radius * cos(_angle)),
                    y = _point.y + _nearest(radius * sin(_angle));
                _angle += _angleFactor;
                if (_map.isOutOfMap(x, y))
                    continue;
                _cellsPerLoop[radius]++;

                if (_map.cellType(new Point(x, y))['box']) {
                    _current = new Point(x, y);
                    isFound = true;
                    break;
                }
            }
            if (_cellsPerLoop[radius] == 0)
                _isEnd = true;
            if (!isFound) {
                _angle = 0.0;
                radius++;
            } else {
                break;
            }
        }
        return !_isEnd ? _current : null;
    }

    int _nearest(double val) {
        if ((val - val.truncate()).abs() < 0.1)
            return val.truncate();
        return val < 0 ? val.floor() : val.ceil();
    }
}

class AStar {
    GameMap _map;
    BombsWatcher bombsWatcher;

    AStar(this._map, this.bombsWatcher);

    /**
     * Returns path list from [from] to [to].
     */
    List<Point> path(Point from, Point to) {
        Logger.debug('searching path ${from} ${to}');
        // game does not support diagonal moves
        var neighborX = [1, 0, -1, 0];
        var neighborY = [0, 1, 0, -1];
        Point current;
        List<Point> closedSet = [];
        List<Point> openSet = [from];
        Map<Point, Point> cameFrom = {};
        var gScore = {from: 0};
        var fScore = {from: from.distanceTo(to)};
        while (!openSet.isEmpty) {
            current = openSet.reduce((first, second) =>
            fScore[first] < fScore[second] ? first : second);
            if (current == to)
                return _getPath(cameFrom, current);
            openSet.remove(current);
            closedSet.add(current);
            for (var i = 0; i < 4; i++) {
                var x = current.x + neighborX[i];
                var y = current.y + neighborY[i];
                var neighbor = new Point(x, y);
                if (_map.isOutOfMap(x, y))
                    continue;
                var type = _map.cellType(neighbor);
                // boxes are obstacles, but only when it's not target box
                if (neighbor != to && (type['obstacle'] || bombsWatcher.isBomb(neighbor)))
                    continue;
                if (closedSet.contains(neighbor))
                    continue;
                var cameFromTmp = new Map.from(cameFrom);
                cameFromTmp[neighbor] = current;
                var path = _getPath(cameFromTmp, neighbor);
                if (bombsWatcher.isDeadPos(neighbor, path.length, path.length))
                    continue;
                var tentativeGScore = gScore[current] + 1;
                if (!openSet.contains(neighbor))
                    openSet.add(neighbor);
                else if (tentativeGScore >= gScore[neighbor])
                    continue;
                cameFrom[neighbor] = current;
                gScore[neighbor] = tentativeGScore;
                fScore[neighbor] = gScore[neighbor] + neighbor.distanceTo(to);
            }
        }
        Logger.debug('not found');
        return null;
    }

    List<Point> _getPath(Map cameFrom, Point current) {
        var totalPath = [current];
        while (cameFrom.containsKey(current)) {
            current = cameFrom[current];
            totalPath.add(current);
        }
        return totalPath;
    }
}

class Logger {
    static LogLevels level = LogLevels.DISABLE;

    static void debug(message) {
        _log(LogLevels.DEBUG, message);
    }

    static void info(message) {
        _log(LogLevels.INFO, message);
    }

    static void _log(LogLevels _level, message) {
        if (_level.index >= level.index) {
            stderr.writeln(message);
        }
    }
}

enum LogLevels { DEBUG, INFO, DISABLE }