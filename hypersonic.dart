import 'dart:io';
import 'dart:math';

List<List<String>> map = [];
int width;
int height;
List<int> toDestroy;
Map<int, Map> players = {};
Map<int, Map> bombs = {};
int range = 3;

void main() {
    List inputs;
    inputs = stdin.readLineSync().split(' ');
    width = int.parse(inputs[0]);
    height = int.parse(inputs[1]);
    int myId = int.parse(inputs[2]);
    Point target, targetPos;
    List<Point> toDestroy = [];
    // game loop
    while (true) {
        stderr.writeln('loop');
        map.clear();
        for (int i = 0; i < height; i++) {
            var a = stdin.readLineSync();
            stderr.writeln(a);
            map.add(a.split(''));
        }
        players.clear();
        bombs.clear();
        int entities = int.parse(stdin.readLineSync());
        for (int i = 0; i < entities; i++) {
            inputs = stdin.readLineSync().split(' ');
            int entityType = int.parse(inputs[0]);
            int owner = int.parse(inputs[1]);
            Point pos = new Point(int.parse(inputs[2]), int.parse(inputs[3]));
            int param1 = int.parse(inputs[4]);
            int param2 = int.parse(inputs[5]);
            if (entityType==0) {
                players[owner] = {'pos': pos, 'bombs': param1, 'range': param2};
            } else {
                bombs[owner] = {'pos': pos, 'countdown': param1, 'range': param2};
            }
        }
        var action = null;
        var myLocation = players[myId]['pos']/*new Point(5,0)*/;
        stderr.writeln('before algo');
        if (target != null && myLocation==target && players[myId]['bombs']>0 && map[targetPos.y][targetPos.x]=='0') {
            stderr.writeln('BOMB!!!');
            action = 'BOMB';
            target = null;
        }
        if (target == null || map[targetPos.y][targetPos.x]!='0') {
            stderr.writeln('searching');
            var spiralProcessor = new SpiralProcessor(map, myLocation);
            var box, boxes = {};
            while ((box = spiralProcessor.getNext()) != null) {
                stderr.writeln('box near ${box}');
                if (toDestroy.contains(box))
                {
                    stderr.writeln('we contain it');
                    continue;
                }
                var path = AStar.path(myLocation, box);
                boxes[path.length] = {'target': path[1],
                    'pos': path[0]};
            }
            // the last box where we settled a bomb. no more boxes.
            if (boxes.isEmpty) {
                target = new Point(0, 0);
            } else {
                var distances = boxes.keys.toList();
                stderr.writeln('distances ${distances}');
                distances.sort();
                box = boxes[distances[0]];
                target = box['target'];
                targetPos = box['pos'];
                stderr.writeln('target ${target}');
                stderr.writeln('toDestroy ${box['pos']}');
                toDestroy.add(targetPos);
                stderr.writeln('toDestroy ${toDestroy}');
            }
        }
        print((action != null ? action : 'MOVE')+' ${target.x} ${target.y}');
        stderr.writeln('end');
    }
}

List<int> getPositionBetween(List<int> point1, List<int> point2) {
    return [(point1[0]-point2[0]).abs().toInt(),
        (point1[1]-point2[1]).abs().toInt()];
}

List<List<int>> getBoxesNear(List<int> point, int range) {
    List<List<int>> directions = [[0, 1], [1, 0], [0, -1], [-1, 0]];
    List<List<int>> boxes = [];
    for (var i = 1; i <= range; i++) {
        directions.forEach((direction) {
            if (map[direction[0] * range][direction[1] * range] != '0')
                return;
            boxes.add([direction[0] * range, direction[1] * range]);
        });
    }
    return boxes;
}

class SpiralProcessor {
    Point _current;
    List<List<String>> _map;
    Point _point;
    int radius = 1;
    bool _isEnd = false;
    double _angle = 0.0;
    Map _cellsPerLoop = {};

    SpiralProcessor(List<List<String>> map, Point point) {
        _map = map;
        _point = point;
    }

    Point getNext() {
        bool isFound = false;
        while (!_isEnd) {
            var _angleFactor = PI/2/(radius*2);
            _cellsPerLoop[radius] ??= 0;
            while (_angle < 2*PI) {
                var x = _point.x+_nearest(radius*cos(_angle)),
                    y = _point.y+_nearest(radius*sin(_angle));
                _angle += _angleFactor;
                if (x < 0 || y < 0 || x >= width || y >= height)
                    continue;
                _cellsPerLoop[radius]++;
                if (_map[y][x] == '0') {
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
    static List<Point> path(Point from, Point to) {
        stderr.writeln('searching path');
        stderr.writeln(from);
        stderr.writeln(to);
        var neighborX = [1, 0, -1, 0];
        var neighborY = [0, 1, 0, -1];
        Point current;
        List<Point> closedSet = [];
        List<Point> openSet = [from];
        Map<Point, Point> cameFrom = {};
        var gScore = {from: 0};
        var fScore = {from: from.distanceTo(to)};
        while (!openSet.isEmpty) {
            current = openSet.reduce((first, second)=>
            fScore[first] < fScore[second] ? first : second);
            if (current == to)
                return _getPath(cameFrom, current);
            openSet.remove(current);
            closedSet.add(current);
            for (var i = 0; i < 4; i++) {
                var x = current.x+neighborX[i];
                var y = current.y+neighborY[i];
                var neighbor = new Point(x, y);
                if (x < 0 || y < 0 || y >= height || x >= width || (neighbor != to && map[y][x] == '0'))
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
        throw new Exception("Can't find path from $from, to $to");
    }

    static List<Point> _getPath(Map cameFrom, Point current) {
        var totalPath = [current];
        while (cameFrom.containsKey(current)) {
            current = cameFrom[current];
            totalPath.add(current);
        }
        return totalPath;
    }
}