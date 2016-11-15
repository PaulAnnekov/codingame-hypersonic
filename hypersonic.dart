import 'dart:io';
import 'dart:math';

int range = 3;
int countdown = 8;
List<Point> directions = [new Point(1, 0), new Point(0, 1),
    new Point(-1, 0), new Point(0, -1)];

void main() {
    Logger.level = LogLevels.INFO;
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

    List<Point> getBoxes() {
        var boxes = [];
        for (int x = 0; x < width; x++) {
            for (int y = 0; y < height; y++) {
                var point = new Point(x, y);
                if (cellType(point)['box'])
                    boxes.add(point);
            }
        }
        return boxes;
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

class Game {
    Map<int, Map> players = {};
    int myId;
    Point target, myLocation;
    GameMap map;
    GameState gameState;
    String nextAction;
    Point nextStep;
    AStar aStar;
    int lastEnemyBomb = 0;
    // TODO: calc must be: owner.free bombs + all owner bombs on map
    int maxBombs = 1;
    Stopwatch watch = new Stopwatch();

    void start() {
        map = new GameMap();
        _readInput();
        while (true) {
            watch.reset();
            watch.start();
            _loop();
        }
    }

    void _readInput() {
        List inputs = stdin.readLineSync().split(' ');
        Logger.info(inputs.join(' '));
        map.width = int.parse(inputs[0]);
        map.height = int.parse(inputs[1]);
        myId = int.parse(inputs[2]);
    }

    void _readEntities() {
        players.clear();
        gameState = new GameState(map);
        int entities = int.parse(stdin.readLineSync());
        Logger.info(entities);
        for (int i = 0; i < entities; i++) {
            List inputs = stdin.readLineSync().split(' ');
            Logger.info(inputs.join(' '));
            int entityType = int.parse(inputs[0]);
            int owner = int.parse(inputs[1]);
            Point pos = new Point(int.parse(inputs[2]), int.parse(inputs[3]));
            int param1 = int.parse(inputs[4]);
            int param2 = int.parse(inputs[5]);
            if (entityType == 0) {
                players[owner] = {'pos': pos, 'bombs': param1, 'range': param2};
            } else if (entityType == 1) {
                gameState.addBombs({pos: {'owner': owner, 'countdown': param1,
                    'range': param2}});
            } else if (entityType == 2) {
                gameState.addBonuses({pos: param1});
            }
        }
    }

    Map _getNextTarget(GameState _gameState, Point _myLocation, List<Point> targetBoxes, [List<Point> excludeBoxes]) {
        Logger.debug('searching');
        if (excludeBoxes == null) {
            excludeBoxes = [];
        }
        // TODO: can happen when we wait for free bomb near our bomb.
        if (_gameState.isDeadPos(_myLocation, 0, 0))
            return null;
        AStar _aStar = new AStar(_gameState);
        var targetBox;
        targetBoxes.removeWhere((box) => excludeBoxes.contains(box));
        if (targetBoxes.isNotEmpty) {
            targetBox = _aStar.path(_myLocation, targetBoxes);
        }
        if (targetBox != null) {
            var target = targetBox[1];
            var isSettle = targetBox.length == 2;
            var nextStep, newStep = targetBox.length-2, action = 'MOVE';
            var haveBombs = _gameState.freeBombsAtStep(myId, maxBombs, newStep) > 0;
            if (!haveBombs) {
                // TODO: if we don't have a bomb, but staying just near we get wrong value.
                nextStep = targetBox[targetBox.length - 2];
                // TODO: maxBombs can change during moving and finding bonuses. Move to GameState.
                newStep = max(newStep, _gameState.stepsToFreeBomb(myId, maxBombs));
            } else if (isSettle) {
                nextStep = null;
                newStep = 0;
                action = 'BOMB';
            } else {
                nextStep = targetBox[targetBox.length - 2];
            }
            var newState = _gameState.cloneStep(newStep);
            newState.addBombs({target: {
                'owner': myId,
                'countdown': countdown,
                'range': players[myId]['range']
            }});
            return {
                'action': action,
                'nextStep': nextStep,
                'destination': targetBox[1],
                'newState': newState,
                'target': targetBox[0]
            };
        } else {
            Map enemies = new Map.from(players);
            enemies.remove(myId);
            var _aStar = new AStar(_gameState);
            List<Point> bombPlaces = [];
            enemies.forEach((id, info) {
                bombPlaces.addAll(_gameState.getPlayerBombSides(info['pos'], players[myId]['range']));
            });
            bombPlaces.removeWhere((point) => excludeBoxes.contains(point));
            List<Point> path = _aStar.path(_myLocation, bombPlaces);
            if (path == null)
                return null;
            var isSettle = path.length == 1;
            var newState = _gameState.cloneStep(isSettle ? 0 : path.length-1);
            newState.addBombs({path[0]: {
                'owner': myId,
                'countdown': countdown,
                'range': players[myId]['range']
            }});
            return {
                'action': isSettle ? 'BOMB' : 'MOVE',
                'nextStep': isSettle ? null : path[path.length-2],
                'newState': newState,
                'destination': path[0],
                'target': path[0]
            };
        }
    }

    void _checkTarget() {
        List<Map> states = [{
            'gameState': gameState,
            'myLocation': myLocation,
            'exclude': []
        }];
        Logger.info('checkTarget: ${watch.elapsedMilliseconds}');
        do {
            var state = states.last;
            // We can go back to recalc previous state, so remove it's previous result
            state['result'] = null;
            var previous = states.length > 1 ? states[states.length-2] : null;
            var targetBoxes = state['gameState'].getTargetBoxes();
            var result = _getNextTarget(state['gameState'], state['myLocation'], targetBoxes, state['exclude']);
            // null - can't get to the box, no boxes left, can't get to the box alive
            if (result != null) {
                state['result'] = result;
                states.add({
                    'gameState': result['newState'],
                    'myLocation': result['destination'],
                    'exclude': []
                });
            } else if (previous != null) {
                previous['exclude'].add(previous['result']['target']);
                states.removeLast();
            }
            Logger.info('state ${states.length} check: ${watch.elapsedMilliseconds}');
        } while (states.length < 4 && states.first['result'] != null);
        var result = states.first['result'];
        if (result != null) {
            // when current action is bomb settlement
            if (result['nextStep'] == null) {
                result['nextStep'] = states[1]['result']['nextStep'];
            }
            target = result['destination'];
            nextAction = result['action'];
            nextStep = result['nextStep'];
            Logger.info('target ${target}');
            Logger.info('toDestroy ${result['target']}');
            Logger.info('nextStep ${result['nextStep']}');
        }
    }

    void _checkOnFire() {
        Logger.debug('_checkOnFire ${nextStep}');
        var fireSides = gameState.isOnFire(nextStep);
        if (fireSides.isEmpty)
            return;
        var currentFireSides = gameState.isOnFire(myLocation);
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
                    gameState.isBomb(choice))
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

    void _loop() {
        Logger.info('loop');
        map.updateFromInput();
        _readEntities();
        aStar = new AStar(gameState);
        myLocation = players[myId]['pos'];
        Logger.debug('before algo');
        nextAction = null;
        _checkTarget();
        // TODO: probably remove
        _checkOnFire();
        if (gameState.isBonusBombNextStep(nextStep))
            maxBombs++;
        print((nextAction != null ? nextAction : 'MOVE') +
            ' ${nextStep.x} ${nextStep.y} ${watch.elapsedMilliseconds}');
        Logger.debug('end');
    }
}

class GameState {
    static final List<List<int>> directions = [[1, 0], [0, 1], [-1, 0], [0, -1]];
    Map<int, GameMap> _mapPerStep = {};
    Map<int, Map<Point, Map>> _bombsPerStep = {};
    Map<int, Map<Point, int>> _bonusesPerStep = {};
    Map<int, List<Point>> _fireCellsPerStep = {};
    List<Point> _cellsOnFire;

    GameState(GameMap map) {
        _bombsPerStep[0] = {};
        _bonusesPerStep[0] = {};
        _fireCellsPerStep[0] = [];
        _mapPerStep[0] = map;
    }

    void addBombs(Map<Point, Map> bombs) {
        _bombsPerStep[0].addAll(bombs);
    }

    void addBonuses(Map<Point, int> bonuses) {
        _bonusesPerStep[0].addAll(bonuses);
    }

    /**
     * Get affected items (boxes, bombs, bonuses, cells) by bomb's fire at [pos] on [step].
     */
    Map<String, List<Point>> _getAffected(Point pos, Map info, int step) {
        var map = _mapPerStep[step];
        var bombs = _bombsPerStep[step];
        var bonuses = _bonusesPerStep[step];
        Map<String, List<Point>> affected = {'boxes': [], 'bombs': [], 'bonuses': [], 'cells': []};
        // we check bomb position because it can be on bonus
        if (bonuses.containsKey(pos))
            affected['bonuses'].add(pos);
        affected['cells'].add(pos);
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

    List<Point> getPlayerBombSides(Point pos, int range, [int step = 0]) {
        for (var i = 1; i <= step; i++) {
            _calcStep(i);
        }
        var map = _mapPerStep[step];
        List<Point> cells = [];
        directions.forEach((direction) {
            for (var i = 1; i < range; i++) {
                var cell = new Point(
                    pos.x + direction[0] * i, pos.y + direction[1] * i);
                if (map.isOutOfMap(cell.x, cell.y))
                    break;
                if (isObstacle(cell, step))
                    break;
                cells.add(cell);
            }
        });

        return cells;
    }

    bool isBomb(Point pos, [int step = 0]) {
        for (var i = 1; i <= step; i++) {
            _calcStep(i);
        }
        return _bombsPerStep[step].containsKey(pos);
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

    int freeBombsAtStep(int owner, int maxBombs, int step) {
        for (var i = 1; i <= step; i++) {
            _calcStep(i);
        }
        return maxBombs - _bombsPerStep[step].values.where((bomb) => bomb['owner'] == owner).length;
    }

    bool isDeadPos(Point pos, [int stepFrom = 0, int stepTo]) {
        if (stepTo == null)
            stepTo = stepFrom;
        for (var i = 0; i <= stepTo; i++, _calcStep(i)) {
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
    }

    int getBombCountdown(Point bomb) {
        return _bombsPerStep[0][bomb]['countdown'];
    }

    /**
     * Get all cells on fire for all rounds.
     */
    List<Point> getCellsOnFire() {
        if (_cellsOnFire != null)
            return _cellsOnFire;
        var step = 0;
        List<Point> cells = new List.from(_fireCellsPerStep[0]);
        do {
            step++;
            _calcStep(step);
            cells.addAll(_fireCellsPerStep[step]);
        } while (_bombsPerStep[step].isNotEmpty);
        _cellsOnFire = cells;
        return _cellsOnFire;
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
                    // fire doesn't go behind the box. stop checking behind
                    if (type['box'])
                        break;
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

    List<Point> getTargetBoxes() {
        var step = 0;
        while (_bombsPerStep[step].isNotEmpty) {
            step++;
            _calcStep(step);
        }
        return _mapPerStep[step].getBoxes();
    }

    bool isObstacle(Point cell, [int step = 0]) {
        var map = mapAtStep(step);
        return map.isOutOfMap(cell.x, cell.y) || map.cellType(cell)['obstacle'] || isBomb(cell, step);
    }

    GameState cloneStep(int step) {
        for (var i = 1; i <= step; i++) {
            _calcStep(i);
        }
        var newGameState = new GameState(mapAtStep(step));
        newGameState.addBombs(_bombsPerStep[step]);
        newGameState.addBonuses(_bonusesPerStep[step]);
        // HACK: :(
        newGameState._fireCellsPerStep[0] = _fireCellsPerStep[step];
        return newGameState;
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
    GameState gameState;
    List<Point> _cellsOnFire;
    AStar(this.gameState) {
        _cellsOnFire = gameState.getCellsOnFire();
    }

    /**
     * Returns path list from [from] to [to].
     */
    List<Point> path(Point from, List<Point> to) {
        var map = gameState.mapAtStep(0);
        Logger.debug('searching path ${from} ${to}');
        // game does not support diagonal moves
        var neighborX = [1, 0, -1, 0];
        var neighborY = [0, 1, 0, -1];
        Point current;
        var gScore = {from: 0};
        var fScore = {from: _distance(from, to)};
        Map<Point, Map> bombWait = {};
        List<Point> closedSet = [];
        List<Point> openSet = [from];
        openSet.add(from);
        Map<Point, Point> cameFrom = {};
        while (!openSet.isEmpty) {
            current = openSet.reduce((first, second) => fScore[first] < fScore[second] ? first : second);
            if (to.contains(current))
                return _getPath(cameFrom, bombWait, current);
            openSet.remove(current);
            closedSet.add(current);
            for (var i = 0; i < 4; i++) {
                var x = current.x + neighborX[i];
                var y = current.y + neighborY[i];
                var neighbor = new Point(x, y);
                if (map.isOutOfMap(x, y))
                    continue;
                if (closedSet.contains(neighbor))
                    continue;
                /* Game-specific logic start*/
                var cameFromTmp = new Map.from(cameFrom);
                cameFromTmp[neighbor] = current;
                var bombWaitTmp = new Map.from(bombWait);
                bombWaitTmp.remove(neighbor);
                var path = _getPath(cameFromTmp, bombWaitTmp, neighbor);
                var step = path.length-1;
                map = gameState.mapAtStep(step);
                var waitPoint, waitTime = 0;
                // boxes are obstacles, but only when it's not target box
                if (!to.contains(neighbor) && gameState.isObstacle(neighbor, step)) {
                    if (!gameState.isBomb(neighbor, step))
                        continue;
                    path.any((point) {
                        if (!_cellsOnFire.contains(point)) {
                            waitPoint = point;
                            return true;
                        }
                        return false;
                    });
                    if (waitPoint == null)
                        continue;
                    waitTime = gameState.getBombCountdown(neighbor);
                }
                // Bombs are exploding on the next step before movement defined on previous one, so check if this
                // position is on fire on the next step.
                if (gameState.isDeadPos(neighbor, step+1))
                    continue;
                /* Game-specific logic end*/
                var tentativeGScore = gScore[current] + 1 + waitTime;
                if (openSet.contains(neighbor) && tentativeGScore >= gScore[neighbor])
                    continue;
                /* Game-specific logic start*/
                bombWait[neighbor] = {'waitPoint': waitPoint, 'waitTime': waitTime};
                /* Game-specific logic end*/
                cameFrom[neighbor] = current;
                gScore[neighbor] = tentativeGScore;
                fScore[neighbor] = gScore[neighbor] + _distance(neighbor, to);
                if (!openSet.contains(neighbor))
                    openSet.add(neighbor);
            }
        }
        Logger.debug('not found');
        return null;
    }

    double _distance(Point from, List<Point> to) {
        // TODO: optimize for single [to].
        return to.fold(double.MAX_FINITE, (min, point) {
            var distance = point.distanceTo(from);
            return min > distance ? distance : min;
        });
    }

    List<Point> _getPath(Map cameFrom, Map bombWait, Point current) {
        var totalPath = [current];
        var waitPoints = {};
        while (cameFrom.containsKey(current)) {
            if (bombWait[current] != null && bombWait[current]['waitPoint'] != null) {
                waitPoints[bombWait[current]['waitPoint']] = bombWait[current]['waitTime'];
            }
            current = cameFrom[current];
            totalPath.add(current);
        }
        waitPoints.forEach((point, time) {
            totalPath.insertAll(totalPath.indexOf(point), new List.filled(time, point));
        });
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