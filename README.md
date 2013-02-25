gtfs-feed-poland
================

The set of applications for scraping public transport data and converting to GTFS format.


O co chodzi?
============

Na Hackathonie otwartych danych został zrobiony proof-of-concept, pomysłu, że można automatycznie przekonwertować stronę rozklady.mpk.krakow.pl na bazę danych formatu GTFS.


Założenia
---------

### Dane wejściowe

Serwis [http://rozklady.mkp.krakow.pl] zawiera dane nieprzyjazne maszynom, które nie nadają się w takiej postaci jakiej są opublikowane, do dalszego przetwarzania.

### Dane wyjściowe

Format [https://developers.google.com/transit/gtfs/ GTFS] jest wspólnym formatem wykorzystywanym przez rozmaite serwisy, biblioteki różnych języków oraz są gotowe narzędzia, pozwalające na wizualizację tych danych.

Format to spakowana do archiwum ZIP seria płaskich plików CSV z rozszerzeniem *.txt.


Wyzwania
--------

### Nieprzyjazny HTML (ramki, niesemantyczne nazwy klas)

Utrudnia to korzystanie z selektorów CSS, które zwracają zbyt dużą ilość danych, które trzeba dodatkowo filtrować korzystając z logiki zaszytej w kodzie aplikacji.

### Ogrom danych w serwisie MPK

Lokalna kopia danych, stworzona za pomocą polecenia

```sh
wget -m -np -k http://rozklady.mpk.krakow.pl
```

ma rozmiar ok. 300 MB.

### Brak danych geo

Format GTFS wymaga, aby każdy przystanek w bazie miał podaną lokalizację geograficzną, których MKP nie podaje. Wymaga to utrzymywania osobnej bazy danych. Na potrzeby Hackathonu wykorzystane zostały dane z aplikacji Transportoid.

### Utrudniona nawigacja po serwisie

Dla przykładu: nie ma spisu kierunków (kursów) na tej samej trasie. Tę informację trzeba wyciągać z różnych dokumentów HTML.

### Kursy widmo

Nie wszystkie kursy rozpoczynają się na pierwszym lub kończą na ostatnim przystanku. Przykład: dla linii 1 niektóre przystanki mają po 89 kursów a niektóre po 90. Wymaga to zmiany algorytmu tak, aby pomijać dodatkowe kursy (wykrywanie sytuacji, że na przystanku B pojazd jest wcześniej niż na przystanku A).

Uproszczenia
------------

Pierwsza działająca wersja ma być uproszczona w stosunku do pełnej i sukcesywnie mają być usuwane ograniczenia:

  * Tylko jedna linia
  * Rozkład jedynie dla dni powszednich
  * Tylko jeden kierunek


TODO
----

- [ ] Uspójnienie ID pozycji z bazy GTFS z danymi ze strony MPK
- [ ] Wykrywanie kursu-widma
  
