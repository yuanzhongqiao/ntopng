/*
 *
 * (C) 2013-24 - ntop.org
 *
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software Foundation,
 * Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
 *
 */

#ifndef _PERIODIC_ACTIVITIES_H_
#define _PERIODIC_ACTIVITIES_H_

#include "ntop_includes.h"

class PeriodicActivities {
 private:
  ThreadedActivity *activities[CONST_MAX_NUM_THREADED_ACTIVITIES], *daily, *daily_delayed;
  u_int16_t num_activities;
  ThreadPool *th_pool;
  pthread_t pthreadLoop;
  bool thread_running;

  u_int8_t getNumThreadsPerPool(const char *path,
                                std::vector<char *> *iface_scripts_list,
                                std::vector<char *> *system_scripts_list);

 public:
  PeriodicActivities();
  ~PeriodicActivities();

  void startPeriodicActivitiesLoop();
  void lua(NetworkInterface *iface, lua_State *vm);
  void run();

  inline bool isRunning() { return (thread_running); }
  void forceStartDailyActivity();
};

#endif /* _PERIODIC_ACTIVITIES_H_ */
