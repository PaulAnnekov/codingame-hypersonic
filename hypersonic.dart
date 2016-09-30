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
    Map targetType;
    String nextAction;
    Point nextStep;
    AStar aStar;
    ComplexCheck complexChecker;
    int lastEnemyBomb = 0;

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
            boxes[path.length] = {'path': path};
        }
        var targetBox;
        // if not the last box where we settled a bomb and no more boxes.
        if (boxes.isNotEmpty) {
            var distances = boxes.keys.toList();
            Logger.debug('boxes ${boxes}, distances ${distances}');
            distances.sort();
            targetBox = boxes[distances[0]];
            for (var i = 0; i < distances.length; i++) {
                var checkBox = boxes[distances[i]];
                var checkStep = checkBox['path'][checkBox['path'].length-2];
                if (bombsWatcher.isBomb(myLocation) && _checkDeadLock(checkStep)) {
                    Logger.debug('_checkDeadLock ${checkStep}');
                    Logger.debug('locked');
                    distances.removeAt(0);
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
        nextStep = path != null && path.length > 1 ? path[path.length-2] : myLocation;
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
        myLocation = players[myId]['pos'] /*new Point(5,0)*/;
        Logger.debug('before algo');
        targetType = targetPos != null ? map.cellType(targetPos) : null;
        nextAction = null;
        _checkSettle();
        _checkTarget();
        _checkEnemy();
        _checkOnFire();
        print((nextAction != null ? nextAction : 'MOVE') +
            ' ${nextStep.x} ${nextStep.y}');
        Logger.debug('end');
    }
}

class BombsWatcher {
    Map<Point, Map> _bombs = {};
    static final List<List<int>> directions = [[1, 0], [0, 1], [-1, 0], [0, -1]
    ];
    GameMap _map;

    BombsWatcher(this._map);

    void addBomb(Point pos, Map info) {
        _bombs[pos] = info;
    }

    List<Point> _getAffectedBoxes(Point pos, Map info) {
        List<Point> boxes = [];
        directions.forEach((direction) {
            for (var i = 1; i < info['range']; i++) {
                var cell = new Point(
                    pos.x + direction[0] * i, pos.y + direction[1] * i);
                if (_map.isOutOfMap(cell.x, cell.y))
                    break;
                var type = _map.cellType(cell);
                // wall blocks fire
                if (type['wall'])
                    break;
                if (type['box']) {
                    Logger.debug(
                        'to destroy cell ${cell} from ${pos} by dir ${direction}');
                    boxes.add(cell);
                    break;
                }
            }
        });

        return boxes;
    }

    bool isBomb(Point pos) {
        return _bombs.containsKey(pos);
    }

    /**
     * Is point will be destroyed on next step.
     */
    List<Point> isOnFire(Point point) {
        List<Point> sides = [];
        for (var pos in _bombs.keys) {
            var info = _bombs[pos];
            if (info['countdown'] > 2)
                continue;
            var isKill = false;
            for (var direction in directions) {
                for (var i = 0; i < info['range']; i++) {
                    var cell = new Point(
                        pos.x + direction[0] * i, pos.y + direction[1] * i);
                    if (_map.isOutOfMap(cell.x, cell.y))
                        break;
                    var type = _map.cellType(cell);
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

    List<Point> getAffectedBoxes() {
        List<Point> boxes = [];
        _bombs.forEach((pos, info) {
            boxes.addAll(_getAffectedBoxes(pos, info));
        });
        return boxes;
    }
}

/*List<int> getPositionBetween(List<int> point1, List<int> point2) {
    return [(point1[0]-point2[0]).abs().toInt(),
        (point1[1]-point2[1]).abs().toInt()];
}

List<List<int>> getBoxesNear(List<int> point, int range) {
    List<List<int>> directions = [[0, 1], [1, 0], [0, -1], [-1, 0]];
    List<List<int>> boxes = [];
    for (var i = 1; i <= range; i++) {
        directions.forEach((direction) {
            if (!cellType(new Point(map[direction[0] * range], [direction[1] * range]))['box'])
                return;
            boxes.add([direction[0] * range, direction[1] * range]);
        });
    }
    return boxes;
}*/

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
        //Logger.debug('searching path ${from} ${to}');
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
        //Logger.debug('not found');
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